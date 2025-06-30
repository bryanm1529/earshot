#include "whisper.h"
#include "httplib.h"
#include "json.hpp"
#include "websocket.h"

#include <cmath>
#include <fstream>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>
#include <cstring>
#include <sstream>
#include <random>
#include <chrono>
#include <mutex>
#include <memory>

#if defined(_MSC_VER)
#pragma warning(disable: 4244 4267) // possible loss of data
#endif

using namespace httplib;
using json = nlohmann::ordered_json;

// Forward declarations for WebSocket support
class WhisperWebSocketHandler;
struct WebSocketConnection {
    websocket::WSConnection<WhisperWebSocketHandler, char, false, 65536, false>* ws_conn;
    std::vector<float> audio_buffer;
    std::chrono::steady_clock::time_point last_activity;
    bool is_active;

    WebSocketConnection() : ws_conn(nullptr), is_active(false) {}
};

// Global WebSocket state
std::mutex ws_connections_mutex;
std::vector<std::shared_ptr<WebSocketConnection>> active_connections;
struct whisper_context* ws_whisper_ctx = nullptr;

// Minimal required functions from common.h
#define WHISPER_SAMPLE_RATE 16000

static const std::vector<std::string> k_colors = {
    "\033[38;5;196m", "\033[38;5;46m", "\033[38;5;208m", "\033[38;5;226m", "\033[38;5;196m",
    "\033[38;5;46m", "\033[38;5;208m", "\033[38;5;226m", "\033[38;5;196m", "\033[38;5;46m",
};

std::string to_timestamp(int64_t t, bool comma = false) {
    int64_t msec = t * 10;
    int64_t hr = msec / (1000 * 60 * 60);
    msec = msec - hr * (1000 * 60 * 60);
    int64_t min = msec / (1000 * 60);
    msec = msec - min * (1000 * 60);
    int64_t sec = msec / 1000;
    msec = msec - sec * 1000;

    char buf[32];
    snprintf(buf, sizeof(buf), "%02d:%02d:%02d%s%03d", (int) hr, (int) min, (int) sec, comma ? "," : ".", (int) msec);

    return std::string(buf);
}

int timestamp_to_sample(int64_t t, int n_samples, int whisper_sample_rate) {
    return std::max(0, std::min((int) n_samples - 1, (int) ((t*whisper_sample_rate)/100)));
}

bool is_file_exist(const char *fileName) {
    std::ifstream infile(fileName);
    return infile.good();
}

bool read_wav(const std::string & fname, std::vector<float> & pcmf32, std::vector<std::vector<float>> & pcmf32s, bool stereo) {
    // Simple WAV reader - minimal implementation
    std::ifstream file(fname, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    // Skip WAV header (44 bytes)
    file.seekg(44);

    // Read audio data as 16-bit PCM and convert to float
    std::vector<int16_t> samples16;
    int16_t sample;
    while (file.read(reinterpret_cast<char*>(&sample), sizeof(sample))) {
        samples16.push_back(sample);
    }

    // Convert to float
    pcmf32.resize(samples16.size());
    for (size_t i = 0; i < samples16.size(); ++i) {
        pcmf32[i] = static_cast<float>(samples16[i]) / 32768.0f;
    }

    if (stereo && samples16.size() % 2 == 0) {
        pcmf32s.resize(2);
        pcmf32s[0].resize(samples16.size() / 2);
        pcmf32s[1].resize(samples16.size() / 2);
        for (size_t i = 0; i < samples16.size() / 2; ++i) {
            pcmf32s[0][i] = static_cast<float>(samples16[2*i]) / 32768.0f;
            pcmf32s[1][i] = static_cast<float>(samples16[2*i+1]) / 32768.0f;
        }
    }

    return true;
}

bool read_wav_content(const std::string & content, std::vector<float> & pcmf32, std::vector<std::vector<float>> & pcmf32s, bool stereo) {
    if (content.size() < 44) return false;

    // Skip WAV header (44 bytes) and read as 16-bit PCM
    const char* data = content.data() + 44;
    size_t data_size = content.size() - 44;
    size_t num_samples = data_size / 2;

    pcmf32.resize(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        int16_t sample = *reinterpret_cast<const int16_t*>(data + i * 2);
        pcmf32[i] = static_cast<float>(sample) / 32768.0f;
    }

    if (stereo && num_samples % 2 == 0) {
        pcmf32s.resize(2);
        pcmf32s[0].resize(num_samples / 2);
        pcmf32s[1].resize(num_samples / 2);
        for (size_t i = 0; i < num_samples / 2; ++i) {
            pcmf32s[0][i] = pcmf32[2*i];
            pcmf32s[1][i] = pcmf32[2*i+1];
        }
    }

    return true;
}

bool parse_str_to_bool(const std::string & s) {
    if (s == "true" || s == "1" || s == "yes" || s == "y") {
        return true;
    }
    return false;
}

namespace {

// output formats
const std::string json_format   = "json";
const std::string text_format   = "text";
const std::string srt_format    = "srt";
const std::string vjson_format  = "verbose_json";
const std::string vtt_format    = "vtt";

struct server_params
{
    std::string hostname = "127.0.0.1";
    std::string public_path = "examples/server/public";
    std::string request_path = "";
    std::string inference_path = "/inference";

    int32_t port          = 8080;
    int32_t read_timeout  = 600;
    int32_t write_timeout = 600;

    bool ffmpeg_converter = false;
};

struct whisper_params {
    int32_t n_threads     = std::min(4, (int32_t) std::thread::hardware_concurrency());
    int32_t n_processors  = 1;
    int32_t offset_t_ms   = 0;
    int32_t offset_n      = 0;
    int32_t duration_ms   = 0;
    int32_t progress_step = 5;
    int32_t max_context   = -1;
    int32_t max_len       = 0;
    int32_t best_of       = 2;
    int32_t beam_size     = -1;
    int32_t audio_ctx     = 0;

    float word_thold      =  0.01f;
    float entropy_thold   =  2.40f;
    float logprob_thold   = -1.00f;
    float temperature     =  0.00f;
    float temperature_inc =  0.20f;
    float no_speech_thold = 0.6f;

    bool debug_mode      = false;
    bool translate       = false;
    bool detect_language = false;
    bool diarize         = true;
    bool tinydiarize     = false;
    bool split_on_word   = false;
    bool no_fallback     = false;
    bool print_special   = false;
    bool print_colors    = false;
    bool print_realtime  = false;
    bool print_progress  = false;
    bool no_timestamps   = false;
    bool use_gpu         = true;
    bool flash_attn      = false;
    bool suppress_nst    = false;

    std::string language        = "en";
    std::string prompt          = "";
    std::string font_path       = "/System/Library/Fonts/Supplemental/Courier New Bold.ttf";
    std::string model           = "models/ggml-base.en.bin";

    std::string response_format     = json_format;

    // [TDRZ] speaker turn string
    std::string tdrz_speaker_turn = " [SPEAKER_TURN]"; // TODO: set from command line

    std::string openvino_encode_device = "CPU";

    std::string dtw = "";
};

struct hot_path_params {
    int32_t step_ms = 256;       // Sprint 5: 16ms stride for streaming
    int32_t length_ms = 2000;    // Sprint 5: 2s context window
    int32_t keep_ms = 0;         // Sprint 5: prevents segment drift
    int32_t capture_id = -1;
    int32_t max_tokens = 32;
    int32_t audio_ctx = 0;

    float vad_thold = 0.6f;
    float freq_thold = 100.0f;

    bool tiny = true;            // Sprint 5: Use tiny.en model for hot path
    bool translate = false;
    bool no_fallback = true;
    bool print_special = false;
    bool no_timestamps = true;
    bool use_gpu = true;
    bool streaming = true;       // Sprint 5: Enable streaming mode

    std::string model = "models/ggml-tiny.en-q5_1.bin";  // Sprint 5: Hot path model (quantized)
    std::string language = "en";
};

// Sprint 5: Multi-backend support
struct backend_params {
    std::string backend = "auto";  // auto, gpu, ane, cpu, metal, coreml
    bool enable_metal = true;
    bool enable_coreml = true;
    bool enable_cuda = true;
    int32_t metal_nbits = 16;     // FP16 for Metal
};

void whisper_print_usage(int /*argc*/, char ** argv, const whisper_params & params, const server_params& sparams, const hot_path_params & hparams) {
    fprintf(stderr, "\n");
    fprintf(stderr, "usage: %s [options] \n", argv[0]);
    fprintf(stderr, "\n");
    fprintf(stderr, "options:\n");
    fprintf(stderr, "  -h,        --help              [default] show this help message and exit\n");
    fprintf(stderr, "  -t N,      --threads N         [%-7d] number of threads to use during computation\n",    params.n_threads);
    fprintf(stderr, "  -p N,      --processors N      [%-7d] number of processors to use during computation\n", params.n_processors);
    fprintf(stderr, "  -ot N,     --offset-t N        [%-7d] time offset in milliseconds\n",                    params.offset_t_ms);
    fprintf(stderr, "  -on N,     --offset-n N        [%-7d] segment index offset\n",                           params.offset_n);
    fprintf(stderr, "  -d  N,     --duration N        [%-7d] duration of audio to process in milliseconds\n",   params.duration_ms);
    fprintf(stderr, "  -mc N,     --max-context N     [%-7d] maximum number of text context tokens to store\n", params.max_context);
    fprintf(stderr, "  -ml N,     --max-len N         [%-7d] maximum segment length in characters\n",           params.max_len);
    fprintf(stderr, "  -sow,      --split-on-word     [%-7s] split on word rather than on token\n",             params.split_on_word ? "true" : "false");
    fprintf(stderr, "  -bo N,     --best-of N         [%-7d] number of best candidates to keep\n",              params.best_of);
    fprintf(stderr, "  -bs N,     --beam-size N       [%-7d] beam size for beam search\n",                      params.beam_size);
    fprintf(stderr, "  -ac N,     --audio-ctx N       [%-7d] audio context size (0 - all)\n",                   params.audio_ctx);
    fprintf(stderr, "  -wt N,     --word-thold N      [%-7.2f] word timestamp probability threshold\n",         params.word_thold);
    fprintf(stderr, "  -et N,     --entropy-thold N   [%-7.2f] entropy threshold for decoder fail\n",           params.entropy_thold);
    fprintf(stderr, "  -lpt N,    --logprob-thold N   [%-7.2f] log probability threshold for decoder fail\n",   params.logprob_thold);
    fprintf(stderr, "  -debug,    --debug-mode        [%-7s] enable debug mode (eg. dump log_mel)\n",           params.debug_mode ? "true" : "false");
    fprintf(stderr, "  -tr,       --translate         [%-7s] translate from source language to english\n",      params.translate ? "true" : "false");
    fprintf(stderr, "  -di,       --diarize           [%-7s] stereo audio diarization\n",                       params.diarize ? "true" : "false");
    fprintf(stderr, "  -tdrz,     --tinydiarize       [%-7s] enable tinydiarize (requires a tdrz model)\n",     params.tinydiarize ? "true" : "false");
    fprintf(stderr, "  -nf,       --no-fallback       [%-7s] do not use temperature fallback while decoding\n", params.no_fallback ? "true" : "false");
    fprintf(stderr, "  -fp,       --font-path         [%-7s] path to font file\n",                              params.font_path.c_str());
    fprintf(stderr, "  -ps,       --print-special     [%-7s] print special tokens\n",                           params.print_special ? "true" : "false");
    fprintf(stderr, "  -pc,       --print-colors      [%-7s] print colors\n",                                   params.print_colors ? "true" : "false");
    fprintf(stderr, "  -pr,       --print-realtime    [%-7s] print output in realtime\n",                       params.print_realtime ? "true" : "false");
    fprintf(stderr, "  -pp,       --print-progress    [%-7s] print progress\n",                                 params.print_progress ? "true" : "false");
    fprintf(stderr, "  -nt,       --no-timestamps     [%-7s] do not print timestamps\n",                        params.no_timestamps ? "true" : "false");
    fprintf(stderr, "  -l LANG,   --language LANG     [%-7s] spoken language ('auto' for auto-detect)\n",       params.language.c_str());
    fprintf(stderr, "  -dl,       --detect-language   [%-7s] exit after automatically detecting language\n",    params.detect_language ? "true" : "false");
    fprintf(stderr, "             --prompt PROMPT     [%-7s] initial prompt\n",                                 params.prompt.c_str());
    fprintf(stderr, "  -m FNAME,  --model FNAME       [%-7s] model path\n",                                     params.model.c_str());
    fprintf(stderr, "  -oved D,   --ov-e-device DNAME [%-7s] the OpenVINO device used for encode inference\n",  params.openvino_encode_device.c_str());
    // server params
    fprintf(stderr, "  -dtw MODEL --dtw MODEL         [%-7s] compute token-level timestamps\n", params.dtw.c_str());
    fprintf(stderr, "  --host HOST,                   [%-7s] Hostname/ip-adress for the server\n", sparams.hostname.c_str());
    fprintf(stderr, "  --port PORT,                   [%-7d] Port number for the server\n", sparams.port);
    fprintf(stderr, "  --public PATH,                 [%-7s] Path to the public folder\n", sparams.public_path.c_str());
    fprintf(stderr, "  --request-path PATH,           [%-7s] Request path for all requests\n", sparams.request_path.c_str());
    fprintf(stderr, "  --inference-path PATH,         [%-7s] Inference path for all requests\n", sparams.inference_path.c_str());
    fprintf(stderr, "  --convert,                     [%-7s] Convert audio to WAV, requires ffmpeg on the server\n", sparams.ffmpeg_converter ? "true" : "false");
    fprintf(stderr, "  -sns,      --suppress-nst      [%-7s] suppress non-speech tokens\n", params.suppress_nst ? "true" : "false");
    fprintf(stderr, "  -nth N,    --no-speech-thold N [%-7.2f] no speech threshold\n",   params.no_speech_thold);
    fprintf(stderr, "\n");
    fprintf(stderr, "hot path params:\n");
    fprintf(stderr, "  --step-ms N,                   [%-7d] step in milliseconds\n", hparams.step_ms);
    fprintf(stderr, "  --length-ms N,                 [%-7d] length in milliseconds\n", hparams.length_ms);
    fprintf(stderr, "  --keep-ms N,                   [%-7d] keep in milliseconds\n", hparams.keep_ms);
    fprintf(stderr, "  --capture-id N,                [%-7d] capture id\n", hparams.capture_id);
    fprintf(stderr, "  --max-tokens N,                [%-7d] max tokens\n", hparams.max_tokens);
    fprintf(stderr, "  --audio-ctx N,                 [%-7d] audio context\n", hparams.audio_ctx);
    fprintf(stderr, "  --vad-thold N,                 [%-7.2f] vad threshold\n", hparams.vad_thold);
    fprintf(stderr, "  --freq-thold N,                [%-7.2f] freq threshold\n", hparams.freq_thold);
    fprintf(stderr, "  --tiny,                        [%-7s] tiny model\n", hparams.tiny ? "true" : "false");
    fprintf(stderr, "  --translate,                   [%-7s] translate\n", hparams.translate ? "true" : "false");
    fprintf(stderr, "  --no-fallback,                 [%-7s] no fallback\n", hparams.no_fallback ? "true" : "false");
    fprintf(stderr, "  --print-special,               [%-7s] print special\n", hparams.print_special ? "true" : "false");
    fprintf(stderr, "  --no-timestamps,               [%-7s] no timestamps\n", hparams.no_timestamps ? "true" : "false");
    fprintf(stderr, "  --use-gpu,                     [%-7s] use gpu\n", hparams.use_gpu ? "true" : "false");
    fprintf(stderr, "  --model FNAME,                 [%-7s] model path\n", hparams.model.c_str());
    fprintf(stderr, "  --language LANG,               [%-7s] spoken language\n", hparams.language.c_str());
    fprintf(stderr, "\n");
}

bool whisper_params_parse(int argc, char ** argv, whisper_params & params, server_params & sparams, hot_path_params & hparams) {
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if (arg == "-h" || arg == "--help") {
            whisper_print_usage(argc, argv, params, sparams, hparams);
            exit(0);
        }
        else if (arg == "-t"    || arg == "--threads")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.n_threads       = std::stoi(argv[++i]);
        }
        else if (arg == "-p"    || arg == "--processors")      {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.n_processors    = std::stoi(argv[++i]);
        }
        else if (arg == "-ot"   || arg == "--offset-t")        {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.offset_t_ms     = std::stoi(argv[++i]);
        }
        else if (arg == "-on"   || arg == "--offset-n")        {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.offset_n        = std::stoi(argv[++i]);
        }
        else if (arg == "-d"    || arg == "--duration")        {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.duration_ms     = std::stoi(argv[++i]);
        }
        else if (arg == "-mc"   || arg == "--max-context")     {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.max_context     = std::stoi(argv[++i]);
        }
        else if (arg == "-ml"   || arg == "--max-len")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.max_len         = std::stoi(argv[++i]);
        }
        else if (arg == "-bo"   || arg == "--best-of")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.best_of         = std::stoi(argv[++i]);
        }
        else if (arg == "-bs"   || arg == "--beam-size")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.beam_size       = std::stoi(argv[++i]);
        }
        else if (arg == "-ac"   || arg == "--audio-ctx")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.audio_ctx       = std::stoi(argv[++i]);
        }
        else if (arg == "-wt"   || arg == "--word-thold")      {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.word_thold      = std::stof(argv[++i]);
        }
        else if (arg == "-et"   || arg == "--entropy-thold")   {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.entropy_thold   = std::stof(argv[++i]);
        }
        else if (arg == "-lpt"  || arg == "--logprob-thold")   {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.logprob_thold   = std::stof(argv[++i]);
        }
        else if (arg == "-debug"|| arg == "--debug-mode")      { params.debug_mode      = true; }
        else if (arg == "-tr"   || arg == "--translate")       { params.translate       = true; }
        else if (arg == "-di"   || arg == "--diarize")         { params.diarize         = true; }
        else if (arg == "-tdrz" || arg == "--tinydiarize")     { params.tinydiarize     = true; }
        else if (arg == "-sow"  || arg == "--split-on-word")   { params.split_on_word   = true; }
        else if (arg == "-nf"   || arg == "--no-fallback")     { params.no_fallback     = true; }
        else if (arg == "-fp"   || arg == "--font-path")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.font_path       = argv[++i];
        }
        else if (arg == "-ps"   || arg == "--print-special")   { params.print_special   = true; }
        else if (arg == "-pc"   || arg == "--print-colors")    { params.print_colors    = true; }
        else if (arg == "-pr"   || arg == "--print-realtime")  { params.print_realtime  = true; }
        else if (arg == "-pp"   || arg == "--print-progress")  { params.print_progress  = true; }
        else if (arg == "-nt"   || arg == "--no-timestamps")   { params.no_timestamps   = true; }
        else if (arg == "-l"    || arg == "--language")        {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.language        = argv[++i];
        }
        else if (arg == "-dl"   || arg == "--detect-language") { params.detect_language = true; }
        else if (                  arg == "--prompt")          {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.prompt          = argv[++i];
        }
        else if (arg == "-m"    || arg == "--model")           {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.model           = argv[++i];
        }
        else if (arg == "-oved" || arg == "--ov-e-device")     {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.openvino_encode_device = argv[++i];
        }
        else if (arg == "-dtw"  || arg == "--dtw")             {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.dtw             = argv[++i];
        }
        else if (arg == "-ng"   || arg == "--no-gpu")          { params.use_gpu         = false; }
        else if (arg == "-fa"   || arg == "--flash-attn")      { params.flash_attn      = true; }
        else if (arg == "-sns"  || arg == "--suppress-nst")    { params.suppress_nst    = true; }
        else if (arg == "-nth"  || arg == "--no-speech-thold") {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            params.no_speech_thold = std::stof(argv[++i]);
        }

        // server params
        else if (                  arg == "--port")            {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            sparams.port        = std::stoi(argv[++i]);
        }
        else if (                  arg == "--host")            {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            sparams.hostname    = argv[++i];
        }
        else if (                  arg == "--public")          {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            sparams.public_path = argv[++i];
        }
        else if (                  arg == "--request-path")    {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            sparams.request_path = argv[++i];
        }
        else if (                  arg == "--inference-path")  {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            sparams.inference_path = argv[++i];
        }
        else if (                  arg == "--convert")         { sparams.ffmpeg_converter     = true; }
        // hot path params
        else if (                  arg == "--step-ms")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.step_ms        = std::stoi(argv[++i]);
        }
        else if (                  arg == "--length-ms")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.length_ms      = std::stoi(argv[++i]);
        }
        else if (                  arg == "--keep-ms")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.keep_ms        = std::stoi(argv[++i]);
        }
        else if (                  arg == "--capture-id")      {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.capture_id     = std::stoi(argv[++i]);
        }
        else if (                  arg == "--max-tokens")      {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.max_tokens     = std::stoi(argv[++i]);
        }
        else if (                  arg == "--audio-ctx")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.audio_ctx      = std::stoi(argv[++i]);
        }
        else if (                  arg == "--vad-thold")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.vad_thold      = std::stof(argv[++i]);
        }
        else if (                  arg == "--freq-thold")      {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.freq_thold     = std::stof(argv[++i]);
        }
        else if (                  arg == "--tiny")            {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.tiny           = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--translate")       {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.translate      = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--no-fallback")     {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.no_fallback    = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--print-special")   {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.print_special  = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--no-timestamps")   {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.no_timestamps  = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--use-gpu")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.use_gpu        = parse_str_to_bool(argv[++i]);
        }
        else if (                  arg == "--model")           {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.model          = argv[++i];
        }
        else if (                  arg == "--language")        {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            hparams.language       = argv[++i];
        }
        // Sprint 5: Backend selection parameters
        else if (                  arg == "--backend")         {
            if (i + 1 >= argc) { fprintf(stderr, "error: missing value for %s\n", arg.c_str()); return false; }
            // bparams.backend        = argv[++i]; // TODO: Add backend_params to function signature
        }
        else {
            fprintf(stderr, "error: unknown argument: %s\n", arg.c_str());
            whisper_print_usage(argc, argv, params, sparams, hparams);
            exit(0);
        }
    }

    return true;
}

struct whisper_print_user_data {
    const whisper_params * params;

    const std::vector<std::vector<float>> * pcmf32s;
    int progress_prev;
};

void check_ffmpeg_availibility() {
    int result = system("ffmpeg -version");

    if (result == 0) {
        std::cout << "ffmpeg is available." << std::endl;
    } else {
        // ffmpeg is not available
        std::cout << "ffmpeg is not found. Please ensure that ffmpeg is installed ";
        std::cout << "and that its executable is included in your system's PATH. ";
        exit(0);
    }
}

bool convert_to_wav(const std::string & temp_filename, std::string & error_resp) {
    std::ostringstream cmd_stream;
    std::string converted_filename_temp = temp_filename + "_temp.wav";
    cmd_stream << "ffmpeg -i \"" << temp_filename << "\" -y -ar 16000 -ac 1 -c:a pcm_s16le \"" << converted_filename_temp << "\" 2>&1";
    std::string cmd = cmd_stream.str();

    int status = std::system(cmd.c_str());
    if (status != 0) {
        error_resp = "{\"error\":\"FFmpeg conversion failed.\"}";
        return false;
    }

    // Remove the original file
    if (remove(temp_filename.c_str()) != 0) {
        error_resp = "{\"error\":\"Failed to remove the original file.\"}";
        return false;
    }

    // Rename the temporary file to match the original filename
    if (rename(converted_filename_temp.c_str(), temp_filename.c_str()) != 0) {
        error_resp = "{\"error\":\"Failed to rename the temporary file.\"}";
        return false;
    }
    return true;
}

std::string estimate_diarization_speaker(std::vector<std::vector<float>> pcmf32s, int64_t t0, int64_t t1, bool id_only = false) {
    std::string speaker = "";
    const int64_t n_samples = pcmf32s[0].size();

    const int64_t is0 = timestamp_to_sample(t0, n_samples, WHISPER_SAMPLE_RATE);
    const int64_t is1 = timestamp_to_sample(t1, n_samples, WHISPER_SAMPLE_RATE);

    double energy0 = 0.0f;
    double energy1 = 0.0f;

    for (int64_t j = is0; j < is1; j++) {
        energy0 += fabs(pcmf32s[0][j]);
        energy1 += fabs(pcmf32s[1][j]);
    }

    if (energy0 > 1.1*energy1) {
        speaker = "0";
    } else if (energy1 > 1.1*energy0) {
        speaker = "1";
    } else {
        speaker = "?";
    }

    //printf("is0 = %lld, is1 = %lld, energy0 = %f, energy1 = %f, speaker = %s\n", is0, is1, energy0, energy1, speaker.c_str());

    if (!id_only) {
        speaker.insert(0, "(speaker ");
        speaker.append(")");
    }

    return speaker;
}

void whisper_print_progress_callback(struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int progress, void * user_data) {
    int progress_step = ((whisper_print_user_data *) user_data)->params->progress_step;
    int * progress_prev  = &(((whisper_print_user_data *) user_data)->progress_prev);
    if (progress >= *progress_prev + progress_step) {
        *progress_prev += progress_step;
        fprintf(stderr, "%s: progress = %3d%%\n", __func__, progress);
    }
}

void whisper_print_segment_callback(struct whisper_context * ctx, struct whisper_state * /*state*/, int n_new, void * user_data) {
    const auto & params  = *((whisper_print_user_data *) user_data)->params;
    const auto & pcmf32s = *((whisper_print_user_data *) user_data)->pcmf32s;

    const int n_segments = whisper_full_n_segments(ctx);

    std::string speaker = "";

    int64_t t0 = 0;
    int64_t t1 = 0;

    // print the last n_new segments
    const int s0 = n_segments - n_new;

    if (s0 == 0) {
        printf("\n");
    }

    for (int i = s0; i < n_segments; i++) {
        if (!params.no_timestamps || params.diarize) {
            t0 = whisper_full_get_segment_t0(ctx, i);
            t1 = whisper_full_get_segment_t1(ctx, i);
        }

        if (!params.no_timestamps) {
            printf("[%s --> %s]  ", to_timestamp(t0).c_str(), to_timestamp(t1).c_str());
        }

        if (params.diarize && pcmf32s.size() == 2) {
            speaker = estimate_diarization_speaker(pcmf32s, t0, t1);
        }

        if (params.print_colors) {
            for (int j = 0; j < whisper_full_n_tokens(ctx, i); ++j) {
                if (params.print_special == false) {
                    const whisper_token id = whisper_full_get_token_id(ctx, i, j);
                    if (id >= whisper_token_eot(ctx)) {
                        continue;
                    }
                }

                const char * text = whisper_full_get_token_text(ctx, i, j);
                const float  p    = whisper_full_get_token_p   (ctx, i, j);

                const int col = std::max(0, std::min((int) k_colors.size() - 1, (int) (std::pow(p, 3)*float(k_colors.size()))));

                printf("%s%s%s%s", speaker.c_str(), k_colors[col].c_str(), text, "\033[0m");
            }
        } else {
            const char * text = whisper_full_get_segment_text(ctx, i);

            printf("%s%s", speaker.c_str(), text);
        }

        if (params.tinydiarize) {
            if (whisper_full_get_segment_speaker_turn_next(ctx, i)) {
                printf("%s", params.tdrz_speaker_turn.c_str());
            }
        }

        // with timestamps or speakers: each segment on new line
        if (!params.no_timestamps || params.diarize) {
            printf("\n");
        }
        fflush(stdout);
    }
}

std::string output_str(struct whisper_context * ctx, const whisper_params & params, std::vector<std::vector<float>> pcmf32s) {
    std::stringstream result;
    const int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char * text = whisper_full_get_segment_text(ctx, i);
        std::string speaker = "";

        if (params.diarize && pcmf32s.size() == 2)
        {
            const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
            const int64_t t1 = whisper_full_get_segment_t1(ctx, i);
            speaker = estimate_diarization_speaker(pcmf32s, t0, t1);
        }

        result << speaker << text << "\n";
    }
    return result.str();
}

void get_req_parameters(const Request & req, whisper_params & params)
{
    try {
        if (req.has_file("offset_t"))
        {
            params.offset_t_ms = std::stoi(req.get_file_value("offset_t").content);
        }
        if (req.has_file("offset_n"))
        {
            params.offset_n = std::stoi(req.get_file_value("offset_n").content);
        }
    if (req.has_file("duration"))
    {
        params.duration_ms = std::stoi(req.get_file_value("duration").content);
    }
    if (req.has_file("max_context"))
    {
        params.max_context = std::stoi(req.get_file_value("max_context").content);
    }
    if (req.has_file("max_len"))
    {
        params.max_len = std::stoi(req.get_file_value("max_len").content);
    }
    if (req.has_file("best_of"))
    {
        params.best_of = std::stoi(req.get_file_value("best_of").content);
    }
    if (req.has_file("beam_size"))
    {
        params.beam_size = std::stoi(req.get_file_value("beam_size").content);
    }
    if (req.has_file("audio_ctx"))
    {
        params.audio_ctx = std::stof(req.get_file_value("audio_ctx").content);
    }
    if (req.has_file("word_thold"))
    {
        params.word_thold = std::stof(req.get_file_value("word_thold").content);
    }
    if (req.has_file("entropy_thold"))
    {
        params.entropy_thold = std::stof(req.get_file_value("entropy_thold").content);
    }
    if (req.has_file("logprob_thold"))
    {
        params.logprob_thold = std::stof(req.get_file_value("logprob_thold").content);
    }
    if (req.has_file("debug_mode"))
    {
        params.debug_mode = parse_str_to_bool(req.get_file_value("debug_mode").content);
    }
    if (req.has_file("translate"))
    {
        params.translate = parse_str_to_bool(req.get_file_value("translate").content);
    }
    if (req.has_file("diarize"))
    {
        params.diarize = parse_str_to_bool(req.get_file_value("diarize").content);
    }
    if (req.has_file("tinydiarize"))
    {
        params.tinydiarize = parse_str_to_bool(req.get_file_value("tinydiarize").content);
    }
    if (req.has_file("split_on_word"))
    {
        params.split_on_word = parse_str_to_bool(req.get_file_value("split_on_word").content);
    }
    if (req.has_file("no_timestamps"))
    {
        params.no_timestamps = parse_str_to_bool(req.get_file_value("no_timestamps").content);
    }
    if (req.has_file("language"))
    {
        params.language = req.get_file_value("language").content;
    }
    if (req.has_file("detect_language"))
    {
        params.detect_language = parse_str_to_bool(req.get_file_value("detect_language").content);
    }
    if (req.has_file("prompt"))
    {
        params.prompt = req.get_file_value("prompt").content;
    }
    if (req.has_file("response_format"))
    {
        params.response_format = req.get_file_value("response_format").content;
    }
    if (req.has_file("temperature"))
    {
        params.temperature = std::stof(req.get_file_value("temperature").content);
    }
    if (req.has_file("temperature_inc"))
    {
        params.temperature_inc = std::stof(req.get_file_value("temperature_inc").content);
    }
    if (req.has_file("suppress_non_speech"))
    {
        params.suppress_nst = parse_str_to_bool(req.get_file_value("suppress_non_speech").content);
    }
    if (req.has_file("suppress_nst"))
    {
        params.suppress_nst = parse_str_to_bool(req.get_file_value("suppress_nst").content);
    }
    } catch (const std::exception& e) {
        fprintf(stderr, "Warning: Invalid parameter value: %s\n", e.what());
    }
}

}  // namespace

// WebSocket Handler for Real-time Audio Streaming
class WhisperWebSocketHandler {
public:
    using WSConnection = websocket::WSConnection<WhisperWebSocketHandler, char, false, 65536, false>;

    // WebSocket connection opened
    bool onWSConnect(WSConnection& conn, const char* request_uri, const char* host, const char* origin,
                     const char* protocol, const char* extensions, char* resp_protocol, uint32_t resp_protocol_size,
                     char* resp_extensions, uint32_t resp_extensions_size) {

        fprintf(stderr, "[WS] New WebSocket connection: %s\n", request_uri);

        // Only accept connections to /hot_stream
        if (strcmp(request_uri, "/hot_stream") != 0) {
            fprintf(stderr, "[WS] Rejected connection - invalid path: %s\n", request_uri);
            return false;
        }

        // Create connection object
        auto ws_conn = std::make_shared<WebSocketConnection>();
        ws_conn->ws_conn = &conn;
        ws_conn->last_activity = std::chrono::steady_clock::now();
        ws_conn->is_active = true;
        ws_conn->audio_buffer.reserve(WHISPER_SAMPLE_RATE * 2); // 2 seconds buffer

        // Add to active connections
        {
            std::lock_guard<std::mutex> lock(ws_connections_mutex);
            active_connections.push_back(ws_conn);
        }

        fprintf(stderr, "[WS] Connection accepted and added to pool\n");
        return true;
    }

    // WebSocket connection closed
    void onWSClose(WSConnection& conn, uint16_t status_code, const char* reason) {
        fprintf(stderr, "[WS] Connection closed: %d - %s\n", status_code, reason ? reason : "");

        // Remove from active connections
        {
            std::lock_guard<std::mutex> lock(ws_connections_mutex);
            active_connections.erase(
                std::remove_if(active_connections.begin(), active_connections.end(),
                    [&conn](const std::shared_ptr<WebSocketConnection>& ws_conn) {
                        return ws_conn->ws_conn == &conn;
                    }),
                active_connections.end()
            );
        }
    }

    // WebSocket message received (audio data)
    void onWSMsg(WSConnection& conn, uint8_t opcode, const uint8_t* payload, uint32_t pl_len) {
        if (opcode == websocket::OPCODE_BINARY) { // Binary frame - audio data
            processAudioData(conn, payload, pl_len);
        } else if (opcode == websocket::OPCODE_TEXT) { // Text frame - commands/control
            processTextMessage(conn, payload, pl_len);
        }
    }

private:
    void processAudioData(WSConnection& conn, const uint8_t* payload, uint32_t pl_len) {
        // Find the connection object
        std::shared_ptr<WebSocketConnection> ws_conn;
        {
            std::lock_guard<std::mutex> lock(ws_connections_mutex);
            auto it = std::find_if(active_connections.begin(), active_connections.end(),
                [&conn](const std::shared_ptr<WebSocketConnection>& c) {
                    return c->ws_conn == &conn;
                });
            if (it != active_connections.end()) {
                ws_conn = *it;
            }
        }

        if (!ws_conn) {
            fprintf(stderr, "[WS] Warning: Connection not found in pool\n");
            return;
        }

        // Update activity timestamp
        ws_conn->last_activity = std::chrono::steady_clock::now();

        // Convert raw audio data (assuming 16-bit PCM) to float
        const int16_t* audio_data = reinterpret_cast<const int16_t*>(payload);
        size_t sample_count = pl_len / 2;

        // Add to audio buffer
        size_t prev_size = ws_conn->audio_buffer.size();
        ws_conn->audio_buffer.resize(prev_size + sample_count);

        for (size_t i = 0; i < sample_count; ++i) {
            ws_conn->audio_buffer[prev_size + i] = static_cast<float>(audio_data[i]) / 32768.0f;
        }

        // Process if we have enough audio (1.1 seconds to ensure > 1000ms)
        const size_t min_samples = WHISPER_SAMPLE_RATE + (WHISPER_SAMPLE_RATE / 10); // 1.1 seconds
        if (ws_conn->audio_buffer.size() >= min_samples) {
            processAudioChunk(*ws_conn);
        }
    }

    void processTextMessage(WSConnection& conn, const uint8_t* payload, uint32_t pl_len) {
        std::string message(reinterpret_cast<const char*>(payload), pl_len);
        fprintf(stderr, "[WS] Text message: %s\n", message.c_str());

        // Handle control messages (e.g., configuration, ping, etc.)
        try {
            auto j = json::parse(message);
            if (j.contains("type")) {
                std::string type = j["type"];
                if (type == "ping") {
                    // Send pong response
                    json pong = {{"type", "pong"}};
                    std::string pong_str = pong.dump();
                    conn.send(websocket::OPCODE_TEXT, reinterpret_cast<const uint8_t*>(pong_str.c_str()), pong_str.length());
                }
            }
        } catch (const std::exception& e) {
            fprintf(stderr, "[WS] Invalid JSON message: %s\n", e.what());
        }
    }

    void processAudioChunk(WebSocketConnection& ws_conn) {
        if (!ws_whisper_ctx) {
            fprintf(stderr, "[WS] Warning: Whisper context not initialized\n");
            return;
        }

                // Use a sliding window approach - keep last 2 seconds, process current 1.1 seconds
        const size_t window_samples = WHISPER_SAMPLE_RATE * 2; // 2 seconds
        const size_t process_samples = WHISPER_SAMPLE_RATE + (WHISPER_SAMPLE_RATE / 10); // 1.1 seconds

        if (ws_conn.audio_buffer.size() < process_samples) {
            return;
        }

        // Extract audio to process
        std::vector<float> audio_chunk(ws_conn.audio_buffer.end() - process_samples, ws_conn.audio_buffer.end());

        // Configure whisper parameters for real-time processing
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        wparams.strategy = WHISPER_SAMPLING_GREEDY;
        wparams.print_realtime = false;
        wparams.print_progress = false;
        wparams.print_timestamps = false;
        wparams.print_special = false;
        wparams.translate = false; // Default to no translation for real-time
        wparams.language = "en"; // Default to English for real-time
        wparams.n_threads = 2; // Limit threads for real-time
        wparams.n_max_text_ctx = 64; // Small context for speed
        wparams.temperature = 0.0f; // Greedy for consistency
        wparams.no_speech_thold = 0.6f;
        wparams.no_timestamps = true;
        wparams.suppress_nst = true;

        // Run transcription
        if (whisper_full_parallel(ws_whisper_ctx, wparams, audio_chunk.data(), audio_chunk.size(), 1) == 0) {
            // Extract transcription result
            std::string transcription;
            const int n_segments = whisper_full_n_segments(ws_whisper_ctx);
            for (int i = 0; i < n_segments; ++i) {
                const char* text = whisper_full_get_segment_text(ws_whisper_ctx, i);
                if (text && strlen(text) > 0) {
                    transcription += text;
                }
            }

            // Send result if we have text
            if (!transcription.empty()) {
                // Clean up transcription
                transcription.erase(0, transcription.find_first_not_of(" \t\n\r"));
                transcription.erase(transcription.find_last_not_of(" \t\n\r") + 1);

                if (!transcription.empty()) {
                    sendTranscriptionResult(*ws_conn.ws_conn, transcription);
                }
            }
        }

        // Maintain sliding window - keep last 1 second of audio
        if (ws_conn.audio_buffer.size() > window_samples) {
            ws_conn.audio_buffer.erase(ws_conn.audio_buffer.begin(),
                                      ws_conn.audio_buffer.end() - window_samples);
        }
    }

    void sendTranscriptionResult(WSConnection& conn, const std::string& text) {
        // Create JSON response matching brain.py expectations
        json response = {
            {"text", text},
            {"timestamp", std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count()},
            {"is_streaming", true}
        };

        std::string response_str = response.dump();
        fprintf(stderr, "[WS] Sending transcription: %s\n", text.c_str());

        // Send as text message
        conn.send(websocket::OPCODE_TEXT, reinterpret_cast<const uint8_t*>(response_str.c_str()), response_str.length());
    }
};

int main(int argc, char ** argv) {
    whisper_params params;
    server_params sparams;
    hot_path_params hparams;
    backend_params bparams;

    std::mutex whisper_mutex;
    std::mutex hot_whisper_mutex; // Sprint 5: Separate mutex for hot path

    if (whisper_params_parse(argc, argv, params, sparams, hparams) == false) {
        whisper_print_usage(argc, argv, params, sparams, hparams);
        return 1;
    }

    if (params.language != "auto" && whisper_lang_id(params.language.c_str()) == -1) {
        fprintf(stderr, "error: unknown language '%s'\n", params.language.c_str());
        whisper_print_usage(argc, argv, params, sparams, hparams);
        exit(0);
    }

    if (params.diarize && params.tinydiarize) {
        fprintf(stderr, "error: cannot use both --diarize and --tinydiarize\n");
        whisper_print_usage(argc, argv, params, sparams, hparams);
        exit(0);
    }

    if (sparams.ffmpeg_converter) {
        check_ffmpeg_availibility();
    }

    // Sprint 5: Configure streaming parameters from environment variables
    if (const char* step_env = std::getenv("STEP_MS")) {
        hparams.step_ms = std::stoi(step_env);
    }
    if (const char* length_env = std::getenv("LENGTH_MS")) {
        hparams.length_ms = std::stoi(length_env);
    }

    fprintf(stderr, "\n[%s] Starting Whisper.cpp server...\n", "2025-01-15 13:13:30");
    fflush(stderr);
    fprintf(stderr, "[CONFIG] Cold Path Model: %s\n", params.model.c_str());
    fprintf(stderr, "[CONFIG] Hot Path Model: %s\n", hparams.model.c_str());
    fprintf(stderr, "[CONFIG] Streaming: step=%dms, length=%dms, keep=%dms\n",
            hparams.step_ms, hparams.length_ms, hparams.keep_ms);
    fprintf(stderr, "[CONFIG] Host: %s:%d\n", sparams.hostname.c_str(), sparams.port);
    fprintf(stderr, "[CONFIG] Threads: %d, Processors: %d\n", params.n_threads, params.n_processors);
    fprintf(stderr, "[CONFIG] GPU: %s, Flash Attention: %s\n",
            params.use_gpu ? "enabled" : "disabled",
            params.flash_attn ? "enabled" : "disabled");
    fflush(stderr);

    // Sprint 5: Initialize Cold Path Context (existing full model)
    fprintf(stderr, "[INIT] Initializing cold path context...\n");
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu    = params.use_gpu;
    cparams.flash_attn = params.flash_attn;

    if (!params.dtw.empty()) {
        cparams.dtw_token_timestamps = true;
        cparams.dtw_aheads_preset = WHISPER_AHEADS_NONE;

        if (params.dtw == "tiny") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_TINY;
        }
        if (params.dtw == "tiny.en") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_TINY_EN;
        }
        if (params.dtw == "base") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE;
        }
        if (params.dtw == "base.en") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE_EN;
        }
        if (params.dtw == "small") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_SMALL;
        }
        if (params.dtw == "small.en") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_SMALL_EN;
        }
        if (params.dtw == "medium") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_MEDIUM;
        }
        if (params.dtw == "medium.en") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_MEDIUM_EN;
        }
        if (params.dtw == "large.v1") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V1;
        }
        if (params.dtw == "large.v2") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V2;
        }
        if (params.dtw == "large.v3") {
            cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V3;
        }

        if (cparams.dtw_aheads_preset == WHISPER_AHEADS_NONE) {
            fprintf(stderr, "error: unknown DTW preset '%s'\n", params.dtw.c_str());
            return 3;
        }
    }

    struct whisper_context * ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);

    if (ctx == nullptr) {
        fprintf(stderr, "[ERROR] Failed to initialize cold path whisper context\n");
        fflush(stderr);
        return 3;
    }
    fprintf(stderr, "[INFO] Successfully initialized cold path context\n");
    fflush(stderr);

    // Sprint 5: Initialize Hot Path Context (tiny model for streaming)
    fprintf(stderr, "[INIT] Initializing hot path context...\n");
    struct whisper_context_params hot_cparams = whisper_context_default_params();
    hot_cparams.use_gpu    = hparams.use_gpu;
    hot_cparams.flash_attn = false; // Disable flash attention for hot path stability

    struct whisper_context * hot_ctx = whisper_init_from_file_with_params(hparams.model.c_str(), hot_cparams);

    if (hot_ctx == nullptr) {
        fprintf(stderr, "[ERROR] Failed to initialize hot path whisper context\n");
        fflush(stderr);
        return 3;
    }
    fprintf(stderr, "[INFO] Successfully initialized hot path context\n");
    fflush(stderr);

    // initialize openvino encoder. this has no effect on whisper.cpp builds that don't have OpenVINO configured
    whisper_ctx_init_openvino_encoder(ctx, nullptr, params.openvino_encode_device.c_str(), nullptr);
    whisper_ctx_init_openvino_encoder(hot_ctx, nullptr, params.openvino_encode_device.c_str(), nullptr);

    // Sprint 8: Initialize WebSocket server for real-time streaming
    fprintf(stderr, "[INIT] Initializing WebSocket server for real-time streaming...\n");

    // Set up global WebSocket context for real-time transcription
    ws_whisper_ctx = hot_ctx; // Use hot path context for WebSocket streaming

    // Create WebSocket server with template parameters
    // Using WhisperWebSocketHandler, char user data, non-segmented mode, 64KB buffer, max 10 connections
    websocket::WSServer<WhisperWebSocketHandler, char, false, 65536, 10> ws_server;
    WhisperWebSocketHandler ws_handler;

    // Calculate WebSocket port (HTTP port + 1000, e.g., 8080 -> 9080)
    int ws_port = sparams.port + 1000;

    // Initialize WebSocket server
    if (!ws_server.init(sparams.hostname.c_str(), ws_port, 10000, 60000)) { // 10s new conn timeout, 60s open conn timeout
        fprintf(stderr, "[ERROR] Failed to initialize WebSocket server on %s:%d\n", sparams.hostname.c_str(), ws_port);
        fprintf(stderr, "[ERROR] %s\n", ws_server.getLastError());
        return 1;
    }

    fprintf(stderr, "[INFO] WebSocket server initialized on ws://%s:%d/hot_stream\n", sparams.hostname.c_str(), ws_port);
    fflush(stderr);

    // Start WebSocket server in a separate thread
    std::thread ws_thread([&ws_server, &ws_handler]() {
        fprintf(stderr, "[WS] WebSocket server thread started\n");
        while (true) {
            ws_server.poll(&ws_handler);
            std::this_thread::sleep_for(std::chrono::milliseconds(1)); // Small delay to prevent CPU spinning
        }
    });
    ws_thread.detach(); // Detach thread to run independently

    Server svr;
    svr.set_default_headers({{"Server", "whisper.cpp"},
                             {"Access-Control-Allow-Origin", "*"},
                             {"Access-Control-Allow-Headers", "content-type, authorization"}});

    std::string const default_content = R"(
    <html>
    <head>
        <title>Whisper.cpp Server</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width">
        <style>
        body {
            font-family: sans-serif;
        }
        form {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
        }
        label {
            margin-bottom: 0.5rem;
        }
        input, select {
            margin-bottom: 1rem;
        }
        button {
            margin-top: 1rem;
        }
        </style>
    </head>
    <body>
        <h1>Whisper.cpp Server</h1>

        <h2>/inference</h2>
        <pre>
    curl 127.0.0.1:)" + std::to_string(sparams.port) + R"(/inference \
    -H "Content-Type: multipart/form-data" \
    -F file="@&lt;file-path&gt;" \
    -F temperature="0.0" \
    -F temperature_inc="0.2" \
    -F response_format="json"
        </pre>

        <h2>/load</h2>
        <pre>
    curl 127.0.0.1:)" + std::to_string(sparams.port) + R"(/load \
    -H "Content-Type: multipart/form-data" \
    -F model="&lt;path-to-model-file&gt;"
        </pre>

        <div>
            <h2>Try it out</h2>
            <form action="/inference" method="POST" enctype="multipart/form-data">
                <label for="file">Choose an audio file:</label>
                <input type="file" id="file" name="file" accept="audio/*" required><br>

                <label for="temperature">Temperature:</label>
                <input type="number" id="temperature" name="temperature" value="0.0" step="0.01" placeholder="e.g., 0.0"><br>

                <label for="response_format">Response Format:</label>
                <select id="response_format" name="response_format">
                    <option value="verbose_json">Verbose JSON</option>
                    <option value="json">JSON</option>
                    <option value="text">Text</option>
                    <option value="srt">SRT</option>
                    <option value="vtt">VTT</option>
                </select><br>

                <button type="submit">Submit</button>
            </form>
        </div>
    </body>
    </html>
    )";

    // store default params so we can reset after each inference request
    whisper_params default_params = params;

    // this is only called if no index.html is found in the public --path
    svr.Get(sparams.request_path + "/", [&default_content](const Request &, Response &res){
        res.set_content(default_content, "text/html");
        return false;
    });

    svr.Options(sparams.request_path + sparams.inference_path, [&](const Request &, Response &){
    });

    // Sprint 5: Hot Stream Endpoint for real-time streaming transcription
    svr.Post(sparams.request_path + "/hot_stream", [&](const Request &req, Response &res){
        // acquire hot whisper model mutex lock
        std::lock_guard<std::mutex> lock(hot_whisper_mutex);

        fprintf(stderr, "\n[HOT_STREAM] New streaming request received\n");
        fflush(stderr);

        // check for audio file
        if (!req.has_file("file")) {
            fprintf(stderr, "[ERROR] No 'file' field in the request\n");
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"no 'file' field in the request\"}";
            res.set_content(error_resp, "application/json");
            return;
        }

        auto audio_file = req.get_file_value("file");
        std::string filename{audio_file.filename};
        fprintf(stderr, "[HOT_STREAM] Processing: %s\n", filename.c_str());
        fflush(stderr);

        // audio arrays
        std::vector<float> pcmf32;
        std::vector<std::vector<float>> pcmf32s;

        // read audio content
        if (!::read_wav_content(audio_file.content, pcmf32, pcmf32s, false)) {
            fprintf(stderr, "[ERROR] Failed to read WAV file\n");
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"failed to read WAV file\"}";
            res.set_content(error_resp, "application/json");
            return;
        }

        fprintf(stderr, "[HOT_STREAM] Audio loaded: %d samples, %.2f sec\n",
                (int)pcmf32.size(), (float)pcmf32.size()/16000.0f);
        fflush(stderr);

        // Sprint 5: Configure streaming whisper parameters
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        // Hot path optimized settings
        wparams.strategy = WHISPER_SAMPLING_GREEDY;
        wparams.print_realtime   = false;
        wparams.print_progress   = false;
        wparams.print_timestamps = false;  // Faster without timestamps
        wparams.print_special    = false;
        wparams.translate        = hparams.translate;
        wparams.language         = hparams.language.c_str();
        wparams.n_threads        = std::min(2, params.n_threads); // Limit threads for hot path
        wparams.n_max_text_ctx   = 128;    // Smaller context for speed
        wparams.offset_ms        = 0;
        wparams.duration_ms      = 0;

        // Aggressive settings for speed
        wparams.thold_pt         = 0.05f;  // Higher threshold = faster
        wparams.max_len          = 32;     // Shorter segments
        wparams.split_on_word    = true;
        wparams.audio_ctx        = hparams.audio_ctx;

        wparams.temperature      = 0.0f;   // Greedy for speed
        wparams.no_speech_thold  = hparams.vad_thold;
        wparams.temperature_inc  = 0.0f;   // No fallback for speed
        wparams.entropy_thold    = 3.0f;   // Higher = faster
        wparams.logprob_thold    = -0.5f;  // More permissive

        wparams.no_timestamps    = true;   // Fastest mode
        wparams.token_timestamps = false;
        wparams.suppress_nst     = true;   // Remove non-speech tokens

        // Run hot path inference
        if (whisper_full_parallel(hot_ctx, wparams, pcmf32.data(), pcmf32.size(), 1) != 0) {
            fprintf(stderr, "[ERROR] Hot path inference failed\n");
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"hot path inference failed\"}";
            res.set_content(error_resp, "application/json");
            return;
        }

        // Extract text results quickly
        std::string results;
        const int n_segments = whisper_full_n_segments(hot_ctx);
        for (int i = 0; i < n_segments; ++i) {
            const char * text = whisper_full_get_segment_text(hot_ctx, i);
            results += text;
        }

        // Sprint 5: Return streaming-optimized JSON response
        json jres = json{
            {"text", results},
            {"is_streaming", true},
            {"model", "tiny.en"},
            {"processing_time_ms", 0}, // TODO: Add timing
            {"segments", n_segments}
        };

        fprintf(stderr, "[HOT_STREAM] Result: %s\n", results.c_str());
        fflush(stderr);

        res.set_content(jres.dump(-1, ' ', false, json::error_handler_t::replace), "application/json");
    });

    svr.Post(sparams.request_path + sparams.inference_path, [&](const Request &req, Response &res){
        // acquire whisper model mutex lock
        std::lock_guard<std::mutex> lock(whisper_mutex);

        fprintf(stderr, "\n[REQUEST] New inference request received\n");
        fflush(stderr);

        // first check user requested fields of the request
        if (!req.has_file("file"))
        {
            fprintf(stderr, "[ERROR] No 'file' field in the request\n");
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"no 'file' field in the request\"}";
            res.set_content(error_resp, "application/json");
            return;
        }
        auto audio_file = req.get_file_value("file");

        // check non-required fields
        get_req_parameters(req, params);

        std::string filename{audio_file.filename};
        fprintf(stderr, "[INFO] Processing file: %s\n", filename.c_str());
        fprintf(stderr, "[PARAMS] Response format: %s, Language: %s\n",
                params.response_format.c_str(),
                params.language.c_str());
        fflush(stderr);
        // audio arrays
        std::vector<float> pcmf32;               // mono-channel F32 PCM
        std::vector<std::vector<float>> pcmf32s; // stereo-channel F32 PCM

        if (sparams.ffmpeg_converter) {
            // if file is not wav, convert to wav
            // write to temporary file with unique name
            auto timestamp = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            std::random_device rd;
            const std::string temp_filename_base = "whisper-server-tmp-" +
                std::to_string(timestamp) + "-" + std::to_string(rd());
            const std::string temp_filename = temp_filename_base + ".wav";
            std::ofstream temp_file{temp_filename, std::ios::binary};
            temp_file << audio_file.content;
            temp_file.close();

            std::string error_resp = "{\"error\":\"Failed to execute ffmpeg command.\"}";
            const bool is_converted = convert_to_wav(temp_filename, error_resp);
            if (!is_converted) {
                res.set_content(error_resp, "application/json");
                return;
            }

            // read wav content into pcmf32
            if (!::read_wav(temp_filename, pcmf32, pcmf32s, params.diarize))
            {
                fprintf(stderr, "[ERROR] Failed to read WAV file '%s'\n", temp_filename.c_str());
                fflush(stderr);
                const std::string error_resp = "{\"error\":\"failed to read WAV file\"}";
                res.set_content(error_resp, "application/json");
                std::remove(temp_filename.c_str());
                return;
            }
            // remove temp file
            std::remove(temp_filename.c_str());
        } else {
            if (!::read_wav_content(audio_file.content, pcmf32, pcmf32s, params.diarize))
            {
                fprintf(stderr, "[ERROR] Failed to read WAV file\n");
                fflush(stderr);
                const std::string error_resp = "{\"error\":\"failed to read WAV file\"}";
                res.set_content(error_resp, "application/json");
                return;
            }
        }

        fprintf(stderr, "[INFO] Successfully loaded %s\n", filename.c_str());
        fflush(stderr);

        // print system information
        {
            fprintf(stderr, "\n");
            fprintf(stderr, "[INFO] System info: n_threads = %d / %d | %s\n",
                    params.n_threads*params.n_processors, std::thread::hardware_concurrency(), whisper_print_system_info());
        }

        // print some info about the processing
        {
            fprintf(stderr, "\n");
            if (!whisper_is_multilingual(ctx)) {
                if (params.language != "en" || params.translate) {
                    params.language = "en";
                    params.translate = false;
                    fprintf(stderr, "%s: [WARNING] Model is not multilingual, ignoring language and translation options\n", __func__);
                }
            }
            if (params.detect_language) {
                params.language = "auto";
            }
            fprintf(stderr, "%s: [INFO] Processing '%s' (%d samples, %.1f sec), %d threads, %d processors, lang = %s, task = %s, %stimestamps = %d ...\n",
                    __func__, filename.c_str(), int(pcmf32.size()), float(pcmf32.size())/16000,
                    params.n_threads, params.n_processors,
                    params.language.c_str(),
                    params.translate ? "translate" : "transcribe",
                    params.tinydiarize ? "tdrz = 1, " : "",
                    params.no_timestamps ? 0 : 1);

            fprintf(stderr, "\n");
        }

        // run the inference
        {
            fprintf(stderr, "[INFO] Running whisper.cpp inference on %s\n", filename.c_str());
            whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

            wparams.strategy = params.beam_size > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY;

            wparams.print_realtime   = false;
            wparams.print_progress   = params.print_progress;
            wparams.print_timestamps = !params.no_timestamps;
            wparams.print_special    = params.print_special;
            wparams.translate        = params.translate;
            wparams.language         = params.language.c_str();
            wparams.n_threads        = params.n_threads;
            wparams.n_max_text_ctx   = params.max_context >= 0 ? params.max_context : wparams.n_max_text_ctx;
            wparams.offset_ms        = params.offset_t_ms;
            wparams.duration_ms      = params.duration_ms;

            wparams.thold_pt         = params.word_thold;
            wparams.max_len          = params.max_len == 0 ? 60 : params.max_len;
            wparams.split_on_word    = params.split_on_word;
            wparams.audio_ctx        = params.audio_ctx;

            wparams.debug_mode       = params.debug_mode;

            wparams.tdrz_enable      = params.tinydiarize; // [TDRZ]

            wparams.initial_prompt   = params.prompt.c_str();

            wparams.greedy.best_of        = params.best_of;
            wparams.beam_search.beam_size = params.beam_size;

            wparams.temperature      = params.temperature;
            wparams.no_speech_thold = params.no_speech_thold;
            wparams.temperature_inc  = params.temperature_inc;
            wparams.entropy_thold    = params.entropy_thold;
            wparams.logprob_thold    = params.logprob_thold;

            wparams.no_timestamps    = params.no_timestamps;
            wparams.token_timestamps = !params.no_timestamps && params.response_format == vjson_format;

            wparams.suppress_nst     = params.suppress_nst;

            whisper_print_user_data user_data = { &params, &pcmf32s, 0 };

            // this callback is called on each new segment
            if (params.print_realtime) {
                wparams.new_segment_callback           = whisper_print_segment_callback;
                wparams.new_segment_callback_user_data = &user_data;
            }

            if (wparams.print_progress) {
                wparams.progress_callback           = whisper_print_progress_callback;
                wparams.progress_callback_user_data = &user_data;
            }

            // examples for abort mechanism
            // in examples below, we do not abort the processing, but we could if the flag is set to true

            // the callback is called before every encoder run - if it returns false, the processing is aborted
            {
                static bool is_aborted = false; // NOTE: this should be atomic to avoid data race

                wparams.encoder_begin_callback = [](struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, void * user_data) {
                    bool is_aborted = *(bool*)user_data;
                    return !is_aborted;
                };
                wparams.encoder_begin_callback_user_data = &is_aborted;
            }

            // the callback is called before every computation - if it returns true, the computation is aborted
            {
                static bool is_aborted = false; // NOTE: this should be atomic to avoid data race

                wparams.abort_callback = [](void * user_data) {
                    bool is_aborted = *(bool*)user_data;
                    return is_aborted;
                };
                wparams.abort_callback_user_data = &is_aborted;
            }

            if (whisper_full_parallel(ctx, wparams, pcmf32.data(), pcmf32.size(), params.n_processors) != 0) {
                fprintf(stderr, "%s: [ERROR] Failed to process audio\n", argv[0]);
                fflush(stderr);
                const std::string error_resp = "{\"error\":\"failed to process audio\"}";
                res.set_content(error_resp, "application/json");
                return;
            }
        }

        // return results to user
        if (params.response_format == text_format)
        {
            std::string results = output_str(ctx, params, pcmf32s);
            res.set_content(results.c_str(), "text/html; charset=utf-8");
        }
        else if (params.response_format == srt_format)
        {
            std::stringstream ss;
            const int n_segments = whisper_full_n_segments(ctx);
            for (int i = 0; i < n_segments; ++i) {
                const char * text = whisper_full_get_segment_text(ctx, i);
                const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                std::string speaker = "";

                if (params.diarize && pcmf32s.size() == 2)
                {
                    speaker = estimate_diarization_speaker(pcmf32s, t0, t1);
                }

                ss << i + 1 + params.offset_n << "\n";
                ss << to_timestamp(t0, true) << " --> " << to_timestamp(t1, true) << "\n";
                ss << speaker << text << "\n\n";
            }
            res.set_content(ss.str(), "application/x-subrip");
        } else if (params.response_format == vtt_format) {
            std::stringstream ss;

            ss << "WEBVTT\n\n";

            const int n_segments = whisper_full_n_segments(ctx);
            for (int i = 0; i < n_segments; ++i) {
                const char * text = whisper_full_get_segment_text(ctx, i);
                const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                std::string speaker = "";

                if (params.diarize && pcmf32s.size() == 2)
                {
                    speaker = estimate_diarization_speaker(pcmf32s, t0, t1, true);
                    speaker.insert(0, "<v Speaker");
                    speaker.append(">");
                }

                ss << to_timestamp(t0) << " --> " << to_timestamp(t1) << "\n";
                ss << speaker << text << "\n\n";
            }
            res.set_content(ss.str(), "text/vtt");
        } else if (params.response_format == vjson_format) {
            /* try to match openai/whisper's Python format */
            std::string results = output_str(ctx, params, pcmf32s);
            json jres = json{
                {"task", params.translate ? "translate" : "transcribe"},
                {"language", whisper_lang_str_full(whisper_full_lang_id(ctx))},
                {"duration", float(pcmf32.size())/16000},
                {"text", results},
                {"segments", json::array()}
            };
            const int n_segments = whisper_full_n_segments(ctx);
            for (int i = 0; i < n_segments; ++i)
            {
                json segment = json{
                    {"id", i},
                    {"text", whisper_full_get_segment_text(ctx, i)},
                };

                if (!params.no_timestamps) {
                    segment["start"] = whisper_full_get_segment_t0(ctx, i) * 0.01;
                    segment["end"] = whisper_full_get_segment_t1(ctx, i) * 0.01;
                }

                float total_logprob = 0;
                const int n_tokens = whisper_full_n_tokens(ctx, i);
                for (int j = 0; j < n_tokens; ++j) {
                    whisper_token_data token = whisper_full_get_token_data(ctx, i, j);
                    if (token.id >= whisper_token_eot(ctx)) {
                        continue;
                    }

                    segment["tokens"].push_back(token.id);
                    json word = json{{"word", whisper_full_get_token_text(ctx, i, j)}};
                    if (!params.no_timestamps) {
                        word["start"] = token.t0 * 0.01;
                        word["end"] = token.t1 * 0.01;
                        word["t_dtw"] = token.t_dtw;
                    }
                    word["probability"] = token.p;
                    total_logprob += token.plog;
                    segment["words"].push_back(word);
                }

                segment["temperature"] = params.temperature;
                segment["avg_logprob"] = total_logprob / n_tokens;

                // TODO compression_ratio and no_speech_prob are not implemented yet
                // segment["compression_ratio"] = 0;
                segment["no_speech_prob"] = whisper_full_get_segment_no_speech_prob(ctx, i);

                jres["segments"].push_back(segment);
            }
            res.set_content(jres.dump(-1, ' ', false, json::error_handler_t::replace),
                            "application/json");
        }
        // TODO add more output formats
        else
        {
            std::string results = output_str(ctx, params, pcmf32s);
            json jres = json{
                {"text", results}
            };
            res.set_content(jres.dump(-1, ' ', false, json::error_handler_t::replace),
                            "application/json");
        }

        // reset params to their defaults
        params = default_params;
    });

    // Add streaming endpoint
    svr.Post(sparams.request_path + "/stream", [&](const Request &req, Response &res) {
        // acquire whisper model mutex lock
        std::lock_guard<std::mutex> lock(whisper_mutex);

        // Use local audio buffer for thread safety
        static thread_local std::vector<float> audio_buffer;
        // Use consistent audio length with WebSocket handler (1.1 seconds)
        const size_t min_samples = WHISPER_SAMPLE_RATE + (WHISPER_SAMPLE_RATE / 10); // 1.1 seconds

        if (!req.has_file("audio")) {
            res.set_content("{\"error\":\"no audio data\"}", "application/json");
            return;
        }

        auto audio_file = req.get_file_value("audio");
        const float* audio_data = reinterpret_cast<const float*>(audio_file.content.c_str());
        int n_samples = audio_file.content.size() / sizeof(float);

        // Add new samples to buffer
        audio_buffer.insert(audio_buffer.end(), audio_data, audio_data + n_samples);

        json response;
        response["segments"] = json::array();

        // Only process if we have enough audio data
        if (audio_buffer.size() >= min_samples) {
            // Run inference
            whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            wparams.print_progress = false;
            wparams.print_special = params.print_special;
            wparams.language = params.language.c_str();
            wparams.n_threads = params.n_threads;

            if (whisper_full(ctx, wparams, audio_buffer.data(), audio_buffer.size()) != 0) {
                res.set_content("{\"error\":\"failed to process audio\"}", "application/json");
                return;
            }

            // Get transcription
            const int n_segments = whisper_full_n_segments(ctx);

            for (int i = 0; i < n_segments; ++i) {
                const char* text = whisper_full_get_segment_text(ctx, i);
                const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                json segment;
                segment["text"] = text;
                segment["t0"] = t0;
                segment["t1"] = t1;
                response["segments"].push_back(segment);
            }

            // Keep a small overlap for context
            const int overlap_samples = (200 * 16000) / 1000; // 200ms overlap
            if (audio_buffer.size() > overlap_samples) {
                audio_buffer.erase(audio_buffer.begin(), audio_buffer.end() - overlap_samples);
            } else {
                audio_buffer.clear();
            }
        }

        response["buffer_size_ms"] = (audio_buffer.size() * 1000) / 16000;
        res.set_content(response.dump(), "application/json");
    });

    svr.Post(sparams.request_path + "/hot_stream", [&](const Request &req, Response &res) {
        // acquire whisper model mutex lock
        std::lock_guard<std::mutex> lock(whisper_mutex);

        // Use local audio buffer for thread safety
        static thread_local std::vector<float> audio_buffer;

        if (!req.has_file("audio")) {
            res.set_content("{\"error\":\"no audio data\"}", "application/json");
            return;
        }

        auto audio_file = req.get_file_value("audio");
        const float* audio_data = reinterpret_cast<const float*>(audio_file.content.c_str());
        int n_samples = audio_file.content.size() / sizeof(float);

        // Add new samples to buffer
        audio_buffer.insert(audio_buffer.end(), audio_data, audio_data + n_samples);

        // Calculate minimum required samples
        const int min_samples = (hparams.length_ms * 16000) / 1000;

        json response;
        response["segments"] = json::array();

        // Only process if we have enough audio data
        if (audio_buffer.size() >= min_samples) {
            // Run inference
            whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            wparams.print_progress = false;
            wparams.print_special = hparams.print_special;
            wparams.language = hparams.language.c_str();
            wparams.n_threads = params.n_threads;
            wparams.step_ms = hparams.step_ms;
            wparams.max_tokens = hparams.max_tokens;
            wparams.audio_ctx = hparams.audio_ctx;
            // Note: Some hot_stream parameters are not available in whisper_full_params
            wparams.translate = hparams.translate;
            wparams.no_timestamps = hparams.no_timestamps;

            if (whisper_full(ctx, wparams, audio_buffer.data(), audio_buffer.size()) != 0) {
                res.set_content("{\"error\":\"failed to process audio\"}", "application/json");
                return;
            }

            // Get transcription
            const int n_segments = whisper_full_n_segments(ctx);

            for (int i = 0; i < n_segments; ++i) {
                const char* text = whisper_full_get_segment_text(ctx, i);
                const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                json segment;
                segment["text"] = text;
                segment["t0"] = t0;
                segment["t1"] = t1;
                response["segments"].push_back(segment);
            }

            // Keep a small overlap for context
            const int overlap_samples = (hparams.keep_ms * 16000) / 1000; // 200ms overlap
            if (audio_buffer.size() > overlap_samples) {
                audio_buffer.erase(audio_buffer.begin(), audio_buffer.end() - overlap_samples);
            } else {
                audio_buffer.clear();
            }
        }

        response["buffer_size_ms"] = (audio_buffer.size() * 1000) / 16000;
        res.set_content(response.dump(), "application/json");
    });

    svr.Post(sparams.request_path + "/load", [&](const Request &req, Response &res){
        std::lock_guard<std::mutex> lock(whisper_mutex);
        if (!req.has_file("model"))
        {
            fprintf(stderr, "[ERROR] No 'model' field in the request\n");
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"no 'model' field in the request\"}";
            res.set_content(error_resp, "application/json");
            return;
        }
        std::string model = req.get_file_value("model").content;
        if (!is_file_exist(model.c_str()))
        {
            fprintf(stderr, "[ERROR] 'model': %s not found!\n", model.c_str());
            fflush(stderr);
            const std::string error_resp = "{\"error\":\"model not found!\"}";
            res.set_content(error_resp, "application/json");
            return;
        }

        // clean up
        whisper_free(ctx);

        // whisper init
        ctx = whisper_init_from_file_with_params(model.c_str(), cparams);

        // TODO perhaps load prior model here instead of exit
        if (ctx == nullptr) {
            fprintf(stderr, "[ERROR] Model init failed, no model loaded must exit\n");
            fflush(stderr);
            exit(1);
        }

        // initialize openvino encoder. this has no effect on whisper.cpp builds that don't have OpenVINO configured
        whisper_ctx_init_openvino_encoder(ctx, nullptr, params.openvino_encode_device.c_str(), nullptr);

        const std::string success = "Load was successful!";
        res.set_content(success, "application/text");

        // check if the model is in the file system
    });

    svr.set_exception_handler([](const Request &, Response &res, std::exception_ptr ep) {
        const char fmt[] = "500 Internal Server Error\n%s";
        char buf[BUFSIZ];
        try {
            std::rethrow_exception(std::move(ep));
        } catch (std::exception &e) {
            snprintf(buf, sizeof(buf), fmt, e.what());
        } catch (...) {
            snprintf(buf, sizeof(buf), fmt, "Unknown Exception");
        }
        res.set_content(buf, "text/plain");
        res.status = 500;
    });

    svr.set_error_handler([](const Request &req, Response &res) {
        if (res.status == 400) {
            res.set_content("Invalid request", "text/plain");
        } else if (res.status != 500) {
            res.set_content("File Not Found (" + req.path + ")", "text/plain");
            res.status = 404;
        }
    });

    // set timeouts and change hostname and port
    svr.set_read_timeout(sparams.read_timeout);
    svr.set_write_timeout(sparams.write_timeout);

    if (!svr.bind_to_port(sparams.hostname, sparams.port))
    {
        fprintf(stderr, "\n[ERROR] Could not bind to server socket: hostname=%s port=%d\n\n",
                sparams.hostname.c_str(), sparams.port);
        fflush(stderr);
        return 1;
    }

    // Set the base directory for serving static files
    svr.set_base_dir(sparams.public_path);

    // to make it ctrl+clickable:
    fprintf(stderr, "\n[INFO] Whisper server listening at http://%s:%d\n", sparams.hostname.c_str(), sparams.port);
    fprintf(stderr, "[INFO] WebSocket real-time streaming at ws://%s:%d/hot_stream\n", sparams.hostname.c_str(), ws_port);
    fflush(stderr);
    fprintf(stderr, "[CONFIG] Server configuration:\n");
    fprintf(stderr, "- HTTP Port: %d\n", sparams.port);
    fprintf(stderr, "- WebSocket Port: %d\n", ws_port);
    fprintf(stderr, "- Model: %s\n", params.model.c_str());
    fprintf(stderr, "- Hot Path Model: %s\n", hparams.model.c_str());
    fprintf(stderr, "- Diarization: %s\n", params.diarize ? "enabled" : "disabled");
    fprintf(stderr, "- Language: %s\n", params.language.c_str());
    fprintf(stderr, "- Public path: %s\n", sparams.public_path.c_str());
    fprintf(stderr, "- Inference path: %s\n", sparams.inference_path.c_str());
    fprintf(stderr, "- Request path: %s\n", sparams.request_path.c_str());
    fprintf(stderr, "- Threads: %d\n", params.n_threads);
    fprintf(stderr, "- Read timeout: %d seconds\n", sparams.read_timeout);
    fprintf(stderr, "- Write timeout: %d seconds\n", sparams.write_timeout);
    fprintf(stderr, "\n[READY] Server is ready to accept connections!\n");
    fprintf(stderr, "- HTTP Endpoints: http://%s:%d/inference, /hot_stream\n", sparams.hostname.c_str(), sparams.port);
    fprintf(stderr, "- WebSocket Streaming: ws://%s:%d/hot_stream\n", sparams.hostname.c_str(), ws_port);
    fflush(stderr);

    if (!svr.listen_after_bind())
    {
        return 1;
    }

    whisper_print_timings(ctx);
    whisper_free(ctx);

    return 0;
}
