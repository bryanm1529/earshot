use anyhow::{anyhow, Result};
use log::{info, error, debug};
use shared_memory::{Shmem, ShmemConf};
use std::sync::atomic::{AtomicU32, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use interprocess::local_socket::{LocalSocketStream, NamedTypeSupport};
use std::io::Write;

/// Zero-copy IPC for Sprint 4 optimization
/// Replaces HTTP POST bottleneck with direct shared memory communication

const SHARED_MEMORY_SIZE: usize = 16 * 1024 * 1024; // 16MB buffer
const MAX_CHUNK_SIZE: usize = 1024 * 1024; // 1MB max per audio chunk
const SOCKET_NAME: &str = "whisper_ipc_socket";

/// Shared memory header for coordination between Rust and C++
#[repr(C)]
struct SharedHeader {
    /// Write position (atomic)
    write_pos: AtomicU32,
    /// Read position (atomic)
    read_pos: AtomicU32,
    /// Buffer status: 0=empty, 1=data_available, 2=full
    status: AtomicU8,
    /// Chunk size in bytes
    chunk_size: AtomicU32,
    /// Sample rate
    sample_rate: AtomicU32,
    /// Reserved for future use
    _reserved: [u8; 64],
}

impl SharedHeader {
    fn new() -> Self {
        Self {
            write_pos: AtomicU32::new(0),
            read_pos: AtomicU32::new(0),
            status: AtomicU8::new(0),
            chunk_size: AtomicU32::new(0),
            sample_rate: AtomicU32::new(16000),
            _reserved: [0; 64],
        }
    }
}

pub struct ZeroCopyIPC {
    shared_memory: Shmem,
    header_ptr: *mut SharedHeader,
    data_ptr: *mut u8,
    data_size: usize,
    notification_socket: Option<LocalSocketStream>,
}

unsafe impl Send for ZeroCopyIPC {}
unsafe impl Sync for ZeroCopyIPC {}

impl ZeroCopyIPC {
    /// Create or connect to shared memory segment
    pub fn new() -> Result<Self> {
        info!("Initializing zero-copy IPC for Sprint 4 optimization");

        // Create shared memory segment
        let shared_memory = ShmemConf::new()
            .size(SHARED_MEMORY_SIZE)
            .create()
            .or_else(|_| {
                // If creation fails, try to open existing segment
                info!("Shared memory already exists, connecting to existing segment");
                ShmemConf::new().size(SHARED_MEMORY_SIZE).open()
            })
            .map_err(|e| anyhow!("Failed to create/open shared memory: {}", e))?;

        info!("Shared memory segment created/opened: {} bytes", SHARED_MEMORY_SIZE);

        // Get raw pointer to shared memory
        let raw_ptr = shared_memory.as_ptr();

        // Split into header and data sections
        let header_ptr = raw_ptr as *mut SharedHeader;
        let data_ptr = unsafe { raw_ptr.add(std::mem::size_of::<SharedHeader>()) };
        let data_size = SHARED_MEMORY_SIZE - std::mem::size_of::<SharedHeader>();

        // Initialize header if this is a new segment
        unsafe {
            if (*header_ptr).sample_rate.load(Ordering::Relaxed) == 0 {
                info!("Initializing shared memory header");
                std::ptr::write(header_ptr, SharedHeader::new());
            }
        }

        // Try to establish notification socket connection
        let notification_socket = Self::connect_notification_socket().ok();
        if notification_socket.is_some() {
            info!("Notification socket connected successfully");
        } else {
            info!("Notification socket connection failed - will retry");
        }

        Ok(Self {
            shared_memory,
            header_ptr,
            data_ptr,
            data_size,
            notification_socket,
        })
    }

    /// Connect to notification socket for signaling new data
    fn connect_notification_socket() -> Result<LocalSocketStream> {
        use interprocess::local_socket::LocalSocketStream;

        match NamedTypeSupport::query() {
            NamedTypeSupport::OnlyPaths => {
                let socket_path = format!("/tmp/{}", SOCKET_NAME);
                LocalSocketStream::connect(socket_path)
                    .map_err(|e| anyhow!("Failed to connect to notification socket: {}", e))
            }
            NamedTypeSupport::OnlyNamespaced | NamedTypeSupport::Both => {
                LocalSocketStream::connect(SOCKET_NAME)
                    .map_err(|e| anyhow!("Failed to connect to notification socket: {}", e))
            }
        }
    }

    /// Write audio chunk to shared memory (zero-copy)
    pub fn write_audio_chunk(&mut self, audio_data: &[f32], sample_rate: u32) -> Result<()> {
        let chunk_bytes = audio_data.len() * std::mem::size_of::<f32>();

        if chunk_bytes > MAX_CHUNK_SIZE {
            return Err(anyhow!("Audio chunk too large: {} bytes (max: {})", chunk_bytes, MAX_CHUNK_SIZE));
        }

        if chunk_bytes > self.data_size {
            return Err(anyhow!("Audio chunk larger than available buffer space"));
        }

        unsafe {
            let header = &*self.header_ptr;

            // Check if buffer has space
            let current_status = header.status.load(Ordering::Acquire);
            if current_status == 2 { // Buffer full
                debug!("Shared memory buffer full, waiting...");
                return Err(anyhow!("Shared memory buffer full"));
            }

            // Write audio data directly to shared memory
            let write_pos = header.write_pos.load(Ordering::Acquire) as usize;

            // Ensure we don't overflow
            if write_pos + chunk_bytes > self.data_size {
                // Reset to beginning (circular buffer)
                header.write_pos.store(0, Ordering::Release);
                debug!("Resetting write position to beginning of buffer");
            }

            let write_pos = header.write_pos.load(Ordering::Acquire) as usize;
            let dest_ptr = self.data_ptr.add(write_pos) as *mut f32;

            // Zero-copy write - directly copy audio data to shared memory
            std::ptr::copy_nonoverlapping(audio_data.as_ptr(), dest_ptr, audio_data.len());

            // Update metadata atomically
            header.chunk_size.store(chunk_bytes as u32, Ordering::Release);
            header.sample_rate.store(sample_rate, Ordering::Release);
            header.write_pos.store((write_pos + chunk_bytes) as u32, Ordering::Release);
            header.status.store(1, Ordering::Release); // Data available

            debug!("Wrote {} bytes of audio data to shared memory at position {}", chunk_bytes, write_pos);
        }

        // Signal new data availability
        self.notify_whisper_server()?;

        Ok(())
    }

    /// Notify Whisper server that new data is available
    fn notify_whisper_server(&mut self) -> Result<()> {
        // Try to reconnect if socket is None
        if self.notification_socket.is_none() {
            self.notification_socket = Self::connect_notification_socket().ok();
        }

        if let Some(ref mut socket) = self.notification_socket {
            // Send simple notification byte
            match socket.write_all(&[1u8]) {
                Ok(_) => {
                    debug!("Notified Whisper server of new audio data");
                    Ok(())
                }
                Err(e) => {
                    error!("Failed to notify Whisper server: {}", e);
                    self.notification_socket = None; // Reset for reconnection
                    Err(anyhow!("Notification failed: {}", e))
                }
            }
        } else {
            debug!("No notification socket available - Whisper server may not be ready");
            Ok(()) // Don't fail the audio write if notification fails
        }
    }

    /// Get current buffer status for monitoring
    pub fn get_buffer_status(&self) -> (u32, u32, u8) {
        unsafe {
            let header = &*self.header_ptr;
            (
                header.write_pos.load(Ordering::Acquire),
                header.read_pos.load(Ordering::Acquire),
                header.status.load(Ordering::Acquire),
            )
        }
    }

    /// Reset buffer state
    pub fn reset_buffer(&self) {
        unsafe {
            let header = &*self.header_ptr;
            header.write_pos.store(0, Ordering::Release);
            header.read_pos.store(0, Ordering::Release);
            header.status.store(0, Ordering::Release);
            header.chunk_size.store(0, Ordering::Release);
        }
        info!("Reset shared memory buffer state");
    }
}

impl Drop for ZeroCopyIPC {
    fn drop(&mut self) {
        info!("Dropping zero-copy IPC connection");
        if let Some(ref mut socket) = self.notification_socket {
            let _ = socket.write_all(&[0u8]); // Send disconnect signal
        }
    }
}

/// Benchmark function to test IPC performance vs HTTP
pub fn benchmark_ipc_vs_http(audio_data: &[f32], iterations: usize) -> Result<(Duration, Duration)> {
    info!("Starting IPC vs HTTP benchmark with {} iterations", iterations);

    // Benchmark shared memory IPC
    let start = Instant::now();
    let mut ipc = ZeroCopyIPC::new()?;
    for _ in 0..iterations {
        ipc.write_audio_chunk(audio_data, 16000)?;
    }
    let ipc_duration = start.elapsed();

    // Benchmark HTTP (simulated)
    let start = Instant::now();
    let client = reqwest::blocking::Client::new();
    for _ in 0..iterations {
        // Simulate HTTP serialization overhead
        let bytes: Vec<u8> = audio_data.iter()
            .flat_map(|&sample| sample.to_le_bytes().to_vec())
            .collect();

        // Simulate form data creation (without actual HTTP call)
        let _form_data = format!("audio_data_size={}", bytes.len());
    }
    let http_duration = start.elapsed();

    info!("Benchmark results: IPC={:?}, HTTP={:?}, Speedup={:.2}x",
          ipc_duration, http_duration,
          http_duration.as_nanos() as f64 / ipc_duration.as_nanos() as f64);

    Ok((ipc_duration, http_duration))
}