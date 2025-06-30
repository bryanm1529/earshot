#pragma once

#include <cstdint>
#include <vector>
#include <string>
#include <atomic>
#include <memory>
#include <chrono>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#endif

/// Zero-copy IPC for Sprint 4 optimization (C++ side)
/// Reads audio data directly from shared memory created by Rust

namespace whisper_ipc {

const size_t SHARED_MEMORY_SIZE = 16 * 1024 * 1024; // 16MB buffer (matches Rust)
const size_t MAX_CHUNK_SIZE = 1024 * 1024; // 1MB max per audio chunk
const char* SOCKET_NAME = "whisper_ipc_socket";

/// Shared memory header (must match Rust SharedHeader exactly)
#pragma pack(push, 1)
struct SharedHeader {
    std::atomic<uint32_t> write_pos{0};
    std::atomic<uint32_t> read_pos{0};
    std::atomic<uint8_t> status{0};      // 0=empty, 1=data_available, 2=full
    std::atomic<uint32_t> chunk_size{0};
    std::atomic<uint32_t> sample_rate{16000};
    uint8_t _reserved[64]{0};
};
#pragma pack(pop)

class ZeroCopyIPCReader {
private:
    SharedHeader* header_ptr_;
    float* data_ptr_;
    size_t data_size_;

#ifdef _WIN32
    HANDLE shared_memory_handle_;
#else
    int shared_memory_fd_;
#endif

    void* mapped_memory_;
    int notification_socket_;

public:
    ZeroCopyIPCReader() :
        header_ptr_(nullptr),
        data_ptr_(nullptr),
        data_size_(0),
#ifdef _WIN32
        shared_memory_handle_(nullptr),
#else
        shared_memory_fd_(-1),
#endif
        mapped_memory_(nullptr),
        notification_socket_(-1) {}

    ~ZeroCopyIPCReader() {
        cleanup();
    }

    /// Initialize shared memory connection
    bool initialize() {
        printf("[IPC] Initializing zero-copy IPC reader for Sprint 4 optimization\n");

#ifdef _WIN32
        // Windows implementation
        shared_memory_handle_ = OpenFileMapping(
            FILE_MAP_ALL_ACCESS,
            FALSE,
            L"WhisperSharedMemory"
        );

        if (shared_memory_handle_ == nullptr) {
            printf("[IPC] Failed to open shared memory: %lu\n", GetLastError());
            return false;
        }

        mapped_memory_ = MapViewOfFile(
            shared_memory_handle_,
            FILE_MAP_ALL_ACCESS,
            0, 0,
            SHARED_MEMORY_SIZE
        );

        if (mapped_memory_ == nullptr) {
            printf("[IPC] Failed to map shared memory: %lu\n", GetLastError());
            CloseHandle(shared_memory_handle_);
            return false;
        }
#else
        // Linux/macOS implementation
        shared_memory_fd_ = shm_open("/WhisperSharedMemory", O_RDWR, 0666);
        if (shared_memory_fd_ == -1) {
            perror("[IPC] Failed to open shared memory");
            return false;
        }

        mapped_memory_ = mmap(nullptr, SHARED_MEMORY_SIZE,
                             PROT_READ | PROT_WRITE, MAP_SHARED,
                             shared_memory_fd_, 0);

        if (mapped_memory_ == MAP_FAILED) {
            perror("[IPC] Failed to map shared memory");
            close(shared_memory_fd_);
            return false;
        }
#endif

        // Set up pointers
        header_ptr_ = static_cast<SharedHeader*>(mapped_memory_);
        data_ptr_ = reinterpret_cast<float*>(
            static_cast<char*>(mapped_memory_) + sizeof(SharedHeader)
        );
        data_size_ = SHARED_MEMORY_SIZE - sizeof(SharedHeader);

        printf("[IPC] Shared memory mapped successfully: %zu bytes\n", SHARED_MEMORY_SIZE);

        // Set up notification socket
        setup_notification_socket();

        return true;
    }

    /// Set up notification socket to receive new data signals
    void setup_notification_socket() {
#ifndef _WIN32
        notification_socket_ = socket(AF_UNIX, SOCK_STREAM, 0);
        if (notification_socket_ == -1) {
            perror("[IPC] Failed to create notification socket");
            return;
        }

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, std::string("/tmp/" + std::string(SOCKET_NAME)).c_str(),
                sizeof(addr.sun_path) - 1);

        // Remove existing socket file
        unlink(addr.sun_path);

        if (bind(notification_socket_, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
            perror("[IPC] Failed to bind notification socket");
            close(notification_socket_);
            notification_socket_ = -1;
            return;
        }

        if (listen(notification_socket_, 5) == -1) {
            perror("[IPC] Failed to listen on notification socket");
            close(notification_socket_);
            notification_socket_ = -1;
            return;
        }

        printf("[IPC] Notification socket listening on %s\n", addr.sun_path);
#endif
    }

    /// Check if new audio data is available
    bool has_new_data() {
        if (!header_ptr_) return false;

        uint8_t status = header_ptr_->status.load(std::memory_order_acquire);
        return status == 1; // data_available
    }

    /// Read audio chunk from shared memory (zero-copy)
    std::vector<float> read_audio_chunk() {
        if (!header_ptr_ || !data_ptr_) {
            return {};
        }

        // Check if data is available
        uint8_t status = header_ptr_->status.load(std::memory_order_acquire);
        if (status != 1) {
            return {}; // No data available
        }

        uint32_t chunk_size = header_ptr_->chunk_size.load(std::memory_order_acquire);
        uint32_t read_pos = header_ptr_->read_pos.load(std::memory_order_acquire);

        if (chunk_size == 0 || chunk_size > MAX_CHUNK_SIZE) {
            return {};
        }

        size_t num_samples = chunk_size / sizeof(float);

        // Ensure we don't read beyond buffer
        if (read_pos + chunk_size > data_size_) {
            printf("[IPC] Warning: Read position would exceed buffer, resetting\n");
            header_ptr_->read_pos.store(0, std::memory_order_release);
            read_pos = 0;
        }

        // Zero-copy read - direct access to shared memory
        std::vector<float> audio_data(num_samples);
        float* src_ptr = data_ptr_ + (read_pos / sizeof(float));
        std::memcpy(audio_data.data(), src_ptr, chunk_size);

        // Update read position
        header_ptr_->read_pos.store(read_pos + chunk_size, std::memory_order_release);

        // Check if we've caught up to write position
        uint32_t write_pos = header_ptr_->write_pos.load(std::memory_order_acquire);
        if (header_ptr_->read_pos.load(std::memory_order_acquire) >= write_pos) {
            header_ptr_->status.store(0, std::memory_order_release); // Mark as empty
        }

        printf("[IPC] Read %zu samples from shared memory (zero-copy)\n", num_samples);
        return audio_data;
    }

    /// Wait for notification of new data
    bool wait_for_notification(int timeout_ms = 1000) {
#ifdef _WIN32
        // Windows implementation (simplified)
        Sleep(timeout_ms);
        return has_new_data();
#else
        if (notification_socket_ == -1) {
            return has_new_data();
        }

        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(notification_socket_, &readfds);

        struct timeval timeout;
        timeout.tv_sec = timeout_ms / 1000;
        timeout.tv_usec = (timeout_ms % 1000) * 1000;

        int result = select(notification_socket_ + 1, &readfds, nullptr, nullptr, &timeout);

        if (result > 0 && FD_ISSET(notification_socket_, &readfds)) {
            // Accept and immediately close the connection (just a signal)
            int client_socket = accept(notification_socket_, nullptr, nullptr);
            if (client_socket != -1) {
                char buffer[1];
                recv(client_socket, buffer, 1, 0);
                close(client_socket);
                return true;
            }
        }

        return false;
#endif
    }

    /// Get current buffer statistics
    struct BufferStats {
        uint32_t write_pos;
        uint32_t read_pos;
        uint8_t status;
        uint32_t sample_rate;
        size_t available_bytes;
    };

    BufferStats get_buffer_stats() {
        if (!header_ptr_) {
            return {0, 0, 0, 0, 0};
        }

        uint32_t write_pos = header_ptr_->write_pos.load(std::memory_order_acquire);
        uint32_t read_pos = header_ptr_->read_pos.load(std::memory_order_acquire);
        uint8_t status = header_ptr_->status.load(std::memory_order_acquire);
        uint32_t sample_rate = header_ptr_->sample_rate.load(std::memory_order_acquire);

        size_t available_bytes = (write_pos >= read_pos) ?
            (write_pos - read_pos) :
            (data_size_ - read_pos + write_pos);

        return {write_pos, read_pos, status, sample_rate, available_bytes};
    }

private:
    void cleanup() {
        if (notification_socket_ != -1) {
#ifndef _WIN32
            close(notification_socket_);
#endif
            notification_socket_ = -1;
        }

        if (mapped_memory_) {
#ifdef _WIN32
            UnmapViewOfFile(mapped_memory_);
            if (shared_memory_handle_) {
                CloseHandle(shared_memory_handle_);
            }
#else
            munmap(mapped_memory_, SHARED_MEMORY_SIZE);
            if (shared_memory_fd_ != -1) {
                close(shared_memory_fd_);
            }
#endif
            mapped_memory_ = nullptr;
        }
    }
};

/// Performance benchmark for IPC vs HTTP
class IPCBenchmark {
public:
    static void benchmark_read_performance(ZeroCopyIPCReader& ipc_reader, size_t iterations = 1000) {
        printf("[BENCHMARK] Starting IPC read performance test with %zu iterations\n", iterations);

        auto start = std::chrono::high_resolution_clock::now();

        size_t total_samples = 0;
        for (size_t i = 0; i < iterations; ++i) {
            if (ipc_reader.has_new_data()) {
                auto audio_data = ipc_reader.read_audio_chunk();
                total_samples += audio_data.size();
            }
        }

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

        printf("[BENCHMARK] IPC Performance Results:\n");
        printf("  - Duration: %ld μs\n", duration.count());
        printf("  - Iterations: %zu\n", iterations);
        printf("  - Total samples: %zu\n", total_samples);
        printf("  - Avg per iteration: %.2f μs\n",
               static_cast<double>(duration.count()) / iterations);

        if (total_samples > 0) {
            printf("  - Throughput: %.2f MB/s\n",
                   (total_samples * sizeof(float) * 1e6) /
                   (duration.count() * 1024 * 1024));
        }
    }
};

} // namespace whisper_ipc