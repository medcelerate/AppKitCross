// WASAPI output and capture streams and device notifications (ADR-0014, ADR-0028). See
// cwasapi.h.

#include "cwasapi.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <propsys.h>
#include <propidl.h>
#include <ks.h>
#include <ksmedia.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>

// PKEY_Device_FriendlyName, spelled out so no GUID library is needed.
static const PROPERTYKEY kFriendlyName = { { 0xa45c254e, 0xdf1c, 0x4efd, { 0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0 } }, 14 };
static const GUID kSubtypeFloat = { 0x00000003, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 } };
static const GUID kSubtypePCM = { 0x00000001, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 } };

static void setError(char *error, size_t length, const char *what, HRESULT hr) {
    if (!error || length == 0) return;
    snprintf(error, length, "%s (HRESULT 0x%08lx)", what, (unsigned long)hr);
}

static void toUTF8(const wchar_t *wide, char *out, size_t length) {
    if (!out || length == 0) return;
    out[0] = 0;
    if (!wide) return;
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, (int)length, nullptr, nullptr);
    out[length - 1] = 0;
}

static std::wstring toWide(const char *utf8) {
    if (!utf8) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &w[0], n);
    return w;
}

// Balances CoInitializeEx only when this call initialised COM: the Win32 backend keeps
// the main thread in an STA, and RPC_E_CHANGED_MODE must not be followed by an
// uninitialise of that apartment.
struct ComInit {
    bool owned = false;
    ComInit() { HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED); owned = hr == S_OK || hr == S_FALSE; }
    ~ComInit() { if (owned) CoUninitialize(); }
};

template <typename T> struct ComPtr {
    T *p = nullptr;
    ~ComPtr() { if (p) p->Release(); }
    T **operator&() { return &p; }
    T *operator->() { return p; }
    explicit operator bool() const { return p != nullptr; }
};

static IMMDeviceEnumerator *makeEnumerator(char *error, size_t errorLength) {
    IMMDeviceEnumerator *e = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(&e));
    if (FAILED(hr)) { setError(error, errorLength, "CoCreateInstance(MMDeviceEnumerator)", hr); return nullptr; }
    return e;
}

static void describeDevice(IMMDevice *device, CWASAPIDeviceInfo *info) {
    memset(info, 0, sizeof *info);
    LPWSTR id = nullptr;
    if (SUCCEEDED(device->GetId(&id)) && id) { toUTF8(id, info->id, sizeof info->id); CoTaskMemFree(id); }
    ComPtr<IPropertyStore> store;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store))) {
        PROPVARIANT v; PropVariantInit(&v);
        if (SUCCEEDED(store->GetValue(kFriendlyName, &v)) && v.vt == VT_LPWSTR) toUTF8(v.pwszVal, info->name, sizeof info->name);
        PropVariantClear(&v);
    }
    ComPtr<IAudioClient> client;
    if (SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&client)))) {
        WAVEFORMATEX *mix = nullptr;
        if (SUCCEEDED(client->GetMixFormat(&mix)) && mix) {
            info->sampleRate = mix->nSamplesPerSec;
            info->channels = mix->nChannels;
            CoTaskMemFree(mix);
        }
    }
}

static std::vector<CWASAPIDeviceInfo> g_devices;
static std::vector<CWASAPIDeviceInfo> g_inputDevices;

static uint32_t enumerateDevices(EDataFlow flow, std::vector<CWASAPIDeviceInfo> &out, char *error, size_t errorLength) {
    ComInit com;
    out.clear();
    ComPtr<IMMDeviceEnumerator> enumerator;
    enumerator.p = makeEnumerator(error, errorLength);
    if (!enumerator) return 0;
    std::string defaultID;
    {
        ComPtr<IMMDevice> def;
        if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &def))) {
            LPWSTR id = nullptr;
            if (SUCCEEDED(def->GetId(&id)) && id) { char buf[512]; toUTF8(id, buf, sizeof buf); defaultID = buf; CoTaskMemFree(id); }
        }
    }
    ComPtr<IMMDeviceCollection> collection;
    HRESULT hr = enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &collection);
    if (FAILED(hr)) { setError(error, errorLength, "EnumAudioEndpoints", hr); return 0; }
    UINT count = 0;
    collection->GetCount(&count);
    for (UINT i = 0; i < count; i++) {
        ComPtr<IMMDevice> device;
        if (FAILED(collection->Item(i, &device))) continue;
        CWASAPIDeviceInfo info;
        describeDevice(device.p, &info);
        info.isDefault = defaultID == info.id;
        out.push_back(info);
    }
    return (uint32_t)out.size();
}

uint32_t cwasapi_output_device_count(char *error, size_t errorLength) {
    return enumerateDevices(eRender, g_devices, error, errorLength);
}

bool cwasapi_output_device(uint32_t index, CWASAPIDeviceInfo *info) {
    if (index >= g_devices.size() || !info) return false;
    *info = g_devices[index];
    return true;
}

static bool defaultDevice(EDataFlow flow, CWASAPIDeviceInfo *info, char *error, size_t errorLength) {
    ComInit com;
    ComPtr<IMMDeviceEnumerator> enumerator;
    enumerator.p = makeEnumerator(error, errorLength);
    if (!enumerator) return false;
    ComPtr<IMMDevice> device;
    HRESULT hr = enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device);
    if (FAILED(hr)) { setError(error, errorLength, flow == eRender ? "GetDefaultAudioEndpoint: no output device" : "GetDefaultAudioEndpoint: no input device", hr); return false; }
    describeDevice(device.p, info);
    info->isDefault = true;
    return true;
}

bool cwasapi_default_output_device(CWASAPIDeviceInfo *info, char *error, size_t errorLength) {
    return defaultDevice(eRender, info, error, errorLength);
}

uint32_t cwasapi_input_device_count(char *error, size_t errorLength) {
    return enumerateDevices(eCapture, g_inputDevices, error, errorLength);
}

bool cwasapi_input_device(uint32_t index, CWASAPIDeviceInfo *info) {
    if (index >= g_inputDevices.size() || !info) return false;
    *info = g_inputDevices[index];
    return true;
}

bool cwasapi_default_input_device(CWASAPIDeviceInfo *info, char *error, size_t errorLength) {
    return defaultDevice(eCapture, info, error, errorLength);
}

struct CWASAPIStream {
    IMMDevice *device = nullptr;
    IAudioClient *client = nullptr;
    IAudioClient3 *client3 = nullptr;
    IAudioRenderClient *renderClient = nullptr;
    WAVEFORMATEX *format = nullptr;
    HANDLE audioEvent = nullptr;
    HANDLE stopEvent = nullptr;
    HANDLE thread = nullptr;
    cwasapi_render_fn render = nullptr;
    void *context = nullptr;
    CWASAPIStreamInfo info{};
    std::vector<float> scratch;   // for Int16 mix formats
    bool started = false;
};

static bool isFloatFormat(const WAVEFORMATEX *f) {
    if (f->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return f->wBitsPerSample == 32;
    if (f->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        const WAVEFORMATEXTENSIBLE *x = reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(f);
        return IsEqualGUID(x->SubFormat, kSubtypeFloat) && f->wBitsPerSample == 32;
    }
    return false;
}

static bool isInt16Format(const WAVEFORMATEX *f) {
    if (f->wFormatTag == WAVE_FORMAT_PCM) return f->wBitsPerSample == 16;
    if (f->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        const WAVEFORMATEXTENSIBLE *x = reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(f);
        return IsEqualGUID(x->SubFormat, kSubtypePCM) && f->wBitsPerSample == 16;
    }
    return false;
}

CWASAPIStream *cwasapi_open(const char *deviceID, cwasapi_render_fn render, void *context, char *error, size_t errorLength) {
    ComInit com;
    ComPtr<IMMDeviceEnumerator> enumerator;
    enumerator.p = makeEnumerator(error, errorLength);
    if (!enumerator) return nullptr;
    CWASAPIStream *s = new CWASAPIStream();
    s->render = render;
    s->context = context;
    HRESULT hr;
    if (deviceID && deviceID[0]) {
        hr = enumerator->GetDevice(toWide(deviceID).c_str(), &s->device);
        if (FAILED(hr)) { setError(error, errorLength, "GetDevice", hr); cwasapi_close(s); return nullptr; }
    } else {
        hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &s->device);
        if (FAILED(hr)) { setError(error, errorLength, "GetDefaultAudioEndpoint: no output device", hr); cwasapi_close(s); return nullptr; }
    }
    CWASAPIDeviceInfo dinfo;
    describeDevice(s->device, &dinfo);
    strncpy(s->info.deviceName, dinfo.name, sizeof s->info.deviceName - 1);

    hr = s->device->Activate(__uuidof(IAudioClient3), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&s->client3));
    if (SUCCEEDED(hr) && s->client3) {
        s->client = s->client3;
        s->client->AddRef();
    } else {
        hr = s->device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&s->client));
        if (FAILED(hr)) { setError(error, errorLength, "Activate(IAudioClient)", hr); cwasapi_close(s); return nullptr; }
    }
    hr = s->client->GetMixFormat(&s->format);
    if (FAILED(hr) || !s->format) { setError(error, errorLength, "GetMixFormat", hr); cwasapi_close(s); return nullptr; }
    s->info.floatOutput = isFloatFormat(s->format);
    if (!s->info.floatOutput && !isInt16Format(s->format)) {
        // Ask for Float32 at the mix rate and channel count instead.
        WAVEFORMATEXTENSIBLE want{};
        want.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
        want.Format.nChannels = s->format->nChannels;
        want.Format.nSamplesPerSec = s->format->nSamplesPerSec;
        want.Format.wBitsPerSample = 32;
        want.Format.nBlockAlign = want.Format.nChannels * 4;
        want.Format.nAvgBytesPerSec = want.Format.nSamplesPerSec * want.Format.nBlockAlign;
        want.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
        want.Samples.wValidBitsPerSample = 32;
        want.dwChannelMask = s->format->wFormatTag == WAVE_FORMAT_EXTENSIBLE ? reinterpret_cast<WAVEFORMATEXTENSIBLE *>(s->format)->dwChannelMask : (want.Format.nChannels == 1 ? SPEAKER_FRONT_CENTER : SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT);
        want.SubFormat = kSubtypeFloat;
        WAVEFORMATEX *closest = nullptr;
        hr = s->client->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &want.Format, &closest);
        if (closest) CoTaskMemFree(closest);
        if (hr != S_OK) { setError(error, errorLength, "the mix format is neither Float32 nor Int16", hr); cwasapi_close(s); return nullptr; }
        CoTaskMemFree(s->format);
        s->format = reinterpret_cast<WAVEFORMATEX *>(CoTaskMemAlloc(sizeof want));
        memcpy(s->format, &want, sizeof want);
        s->info.floatOutput = true;
    }
    s->info.sampleRate = s->format->nSamplesPerSec;
    s->info.channels = s->format->nChannels;

    bool initialized = false;
    if (s->client3) {
        UINT32 defaultPeriod = 0, fundamental = 0, minPeriod = 0, maxPeriod = 0;
        hr = s->client3->GetSharedModeEnginePeriod(s->format, &defaultPeriod, &fundamental, &minPeriod, &maxPeriod);
        if (SUCCEEDED(hr) && minPeriod > 0) {
            hr = s->client3->InitializeSharedAudioStream(AUDCLNT_STREAMFLAGS_EVENTCALLBACK, minPeriod, s->format, nullptr);
            if (SUCCEEDED(hr)) {
                initialized = true;
                s->info.lowLatency = true;
                s->info.periodFrames = minPeriod;
            }
        }
    }
    if (!initialized) {
        REFERENCE_TIME defaultPeriod = 0, minimumPeriod = 0;
        s->client->GetDevicePeriod(&defaultPeriod, &minimumPeriod);
        hr = s->client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 0, 0, s->format, nullptr);
        if (FAILED(hr)) { setError(error, errorLength, "IAudioClient::Initialize", hr); cwasapi_close(s); return nullptr; }
        s->info.periodFrames = (uint32_t)((double)defaultPeriod * s->format->nSamplesPerSec / 10000000.0 + 0.5);
        if (s->info.periodFrames == 0) s->info.periodFrames = 480;
    }
    UINT32 bufferFrames = 0;
    s->client->GetBufferSize(&bufferFrames);
    s->info.bufferFrames = bufferFrames;
    REFERENCE_TIME latency = 0;
    s->client->GetStreamLatency(&latency);
    s->info.latencySeconds = (double)latency / 10000000.0 + (double)bufferFrames / s->format->nSamplesPerSec;
    s->audioEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    s->stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    hr = s->client->SetEventHandle(s->audioEvent);
    if (FAILED(hr)) { setError(error, errorLength, "SetEventHandle", hr); cwasapi_close(s); return nullptr; }
    hr = s->client->GetService(__uuidof(IAudioRenderClient), reinterpret_cast<void **>(&s->renderClient));
    if (FAILED(hr)) { setError(error, errorLength, "GetService(IAudioRenderClient)", hr); cwasapi_close(s); return nullptr; }
    s->scratch.resize((size_t)bufferFrames * s->format->nChannels);
    return s;
}

void cwasapi_stream_info(CWASAPIStream *stream, CWASAPIStreamInfo *info) {
    if (stream && info) *info = stream->info;
}

static void fillBuffer(CWASAPIStream *s, BYTE *data, UINT32 frames) {
    uint32_t channels = s->format->nChannels;
    if (s->info.floatOutput) {
        s->render(s->context, reinterpret_cast<float *>(data), frames);
    } else {
        float *tmp = s->scratch.data();
        s->render(s->context, tmp, frames);
        int16_t *out = reinterpret_cast<int16_t *>(data);
        size_t n = (size_t)frames * channels;
        for (size_t i = 0; i < n; i++) {
            float v = tmp[i] * 32768.0f;
            if (v > 32767.0f) v = 32767.0f; else if (v < -32768.0f) v = -32768.0f;
            out[i] = (int16_t)v;
        }
    }
}

static DWORD WINAPI renderThread(LPVOID param) {
    CWASAPIStream *s = static_cast<CWASAPIStream *>(param);
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    DWORD taskIndex = 0;
    HANDLE task = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
    // Pre-fill the whole buffer with silence, then start the client.
    BYTE *data = nullptr;
    if (SUCCEEDED(s->renderClient->GetBuffer(s->info.bufferFrames, &data))) s->renderClient->ReleaseBuffer(s->info.bufferFrames, AUDCLNT_BUFFERFLAGS_SILENT);
    s->client->Start();
    HANDLE handles[2] = { s->stopEvent, s->audioEvent };
    for (;;) {
        DWORD r = WaitForMultipleObjects(2, handles, FALSE, 2000);
        if (r == WAIT_OBJECT_0) break;                 // stop
        if (r == WAIT_TIMEOUT) continue;               // the device stalled; keep waiting
        UINT32 padding = 0;
        if (FAILED(s->client->GetCurrentPadding(&padding))) continue;
        UINT32 available = s->info.bufferFrames > padding ? s->info.bufferFrames - padding : 0;
        if (available == 0) continue;
        if (FAILED(s->renderClient->GetBuffer(available, &data))) continue;
        fillBuffer(s, data, available);
        s->renderClient->ReleaseBuffer(available, 0);
    }
    s->client->Stop();
    if (task) AvRevertMmThreadCharacteristics(task);
    CoUninitialize();
    return 0;
}

bool cwasapi_start(CWASAPIStream *stream, char *error, size_t errorLength) {
    if (!stream) return false;
    if (stream->started) return true;
    ResetEvent(stream->stopEvent);
    stream->thread = CreateThread(nullptr, 0, renderThread, stream, 0, nullptr);
    if (!stream->thread) { setError(error, errorLength, "CreateThread", HRESULT_FROM_WIN32(GetLastError())); return false; }
    stream->started = true;
    return true;
}

void cwasapi_stop(CWASAPIStream *stream) {
    if (!stream || !stream->started) return;
    SetEvent(stream->stopEvent);
    WaitForSingleObject(stream->thread, INFINITE);
    CloseHandle(stream->thread);
    stream->thread = nullptr;
    stream->started = false;
    stream->client->Reset();
}

void cwasapi_close(CWASAPIStream *stream) {
    if (!stream) return;
    cwasapi_stop(stream);
    if (stream->renderClient) stream->renderClient->Release();
    if (stream->client3) stream->client3->Release();
    if (stream->client) stream->client->Release();
    if (stream->device) stream->device->Release();
    if (stream->format) CoTaskMemFree(stream->format);
    if (stream->audioEvent) CloseHandle(stream->audioEvent);
    if (stream->stopEvent) CloseHandle(stream->stopEvent);
    delete stream;
}

// MARK: Capture

struct CWASAPICaptureStream {
    IMMDevice *device = nullptr;
    IAudioClient *client = nullptr;
    IAudioCaptureClient *captureClient = nullptr;
    WAVEFORMATEX *format = nullptr;
    HANDLE audioEvent = nullptr;
    HANDLE stopEvent = nullptr;
    HANDLE thread = nullptr;
    cwasapi_capture_fn capture = nullptr;
    void *context = nullptr;
    CWASAPIStreamInfo info{};
    std::vector<float> scratch;     // the packet as Float32
    bool started = false;
};

CWASAPICaptureStream *cwasapi_open_capture(const char *deviceID, cwasapi_capture_fn capture, void *context, char *error, size_t errorLength) {
    ComInit com;
    ComPtr<IMMDeviceEnumerator> enumerator;
    enumerator.p = makeEnumerator(error, errorLength);
    if (!enumerator) return nullptr;
    CWASAPICaptureStream *s = new CWASAPICaptureStream();
    s->capture = capture;
    s->context = context;
    HRESULT hr;
    if (deviceID && deviceID[0]) {
        hr = enumerator->GetDevice(toWide(deviceID).c_str(), &s->device);
        if (FAILED(hr)) { setError(error, errorLength, "GetDevice", hr); cwasapi_capture_close(s); return nullptr; }
    } else {
        hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &s->device);
        if (FAILED(hr)) { setError(error, errorLength, "GetDefaultAudioEndpoint: no input device", hr); cwasapi_capture_close(s); return nullptr; }
    }
    CWASAPIDeviceInfo dinfo;
    describeDevice(s->device, &dinfo);
    strncpy(s->info.deviceName, dinfo.name, sizeof s->info.deviceName - 1);
    hr = s->device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&s->client));
    if (FAILED(hr)) { setError(error, errorLength, "Activate(IAudioClient) for capture", hr); cwasapi_capture_close(s); return nullptr; }
    hr = s->client->GetMixFormat(&s->format);
    if (FAILED(hr) || !s->format) { setError(error, errorLength, "GetMixFormat", hr); cwasapi_capture_close(s); return nullptr; }
    s->info.floatOutput = isFloatFormat(s->format);
    if (!s->info.floatOutput && !isInt16Format(s->format)) { setError(error, errorLength, "the capture mix format is neither Float32 nor Int16", E_FAIL); cwasapi_capture_close(s); return nullptr; }
    s->info.sampleRate = s->format->nSamplesPerSec;
    s->info.channels = s->format->nChannels;
    REFERENCE_TIME defaultPeriod = 0, minimumPeriod = 0;
    s->client->GetDevicePeriod(&defaultPeriod, &minimumPeriod);
    hr = s->client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 0, 0, s->format, nullptr);
    if (FAILED(hr)) { setError(error, errorLength, "IAudioClient::Initialize (capture)", hr); cwasapi_capture_close(s); return nullptr; }
    s->info.periodFrames = (uint32_t)((double)defaultPeriod * s->format->nSamplesPerSec / 10000000.0 + 0.5);
    if (s->info.periodFrames == 0) s->info.periodFrames = 480;
    UINT32 bufferFrames = 0;
    s->client->GetBufferSize(&bufferFrames);
    s->info.bufferFrames = bufferFrames;
    REFERENCE_TIME latency = 0;
    s->client->GetStreamLatency(&latency);
    s->info.latencySeconds = (double)latency / 10000000.0 + (double)s->info.periodFrames / s->format->nSamplesPerSec;
    s->audioEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    s->stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    hr = s->client->SetEventHandle(s->audioEvent);
    if (FAILED(hr)) { setError(error, errorLength, "SetEventHandle (capture)", hr); cwasapi_capture_close(s); return nullptr; }
    hr = s->client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void **>(&s->captureClient));
    if (FAILED(hr)) { setError(error, errorLength, "GetService(IAudioCaptureClient)", hr); cwasapi_capture_close(s); return nullptr; }
    s->scratch.resize((size_t)(bufferFrames > 0 ? bufferFrames : 4800) * s->format->nChannels);
    return s;
}

void cwasapi_capture_info(CWASAPICaptureStream *stream, CWASAPIStreamInfo *info) {
    if (stream && info) *info = stream->info;
}

static DWORD WINAPI captureThread(LPVOID param) {
    CWASAPICaptureStream *s = static_cast<CWASAPICaptureStream *>(param);
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    DWORD taskIndex = 0;
    HANDLE task = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
    s->client->Start();
    HANDLE handles[2] = { s->stopEvent, s->audioEvent };
    const uint32_t channels = s->format->nChannels;
    for (;;) {
        DWORD r = WaitForMultipleObjects(2, handles, FALSE, 2000);
        if (r == WAIT_OBJECT_0) break;
        if (r == WAIT_TIMEOUT) continue;
        UINT32 packet = 0;
        while (SUCCEEDED(s->captureClient->GetNextPacketSize(&packet)) && packet > 0) {
            BYTE *data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            if (FAILED(s->captureClient->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
            size_t samples = (size_t)frames * channels;
            if (samples > s->scratch.size()) s->scratch.resize(samples);   // not expected: packets fit the buffer
            float *out = s->scratch.data();
            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) || !data) {
                memset(out, 0, samples * sizeof(float));
            } else if (s->info.floatOutput) {
                memcpy(out, data, samples * sizeof(float));
            } else {
                const int16_t *in = reinterpret_cast<const int16_t *>(data);
                for (size_t i = 0; i < samples; i++) out[i] = in[i] * (1.0f / 32768.0f);
            }
            if (frames > 0) s->capture(s->context, out, frames);
            s->captureClient->ReleaseBuffer(frames);
        }
    }
    s->client->Stop();
    if (task) AvRevertMmThreadCharacteristics(task);
    CoUninitialize();
    return 0;
}

bool cwasapi_capture_start(CWASAPICaptureStream *stream, char *error, size_t errorLength) {
    if (!stream) return false;
    if (stream->started) return true;
    ResetEvent(stream->stopEvent);
    stream->thread = CreateThread(nullptr, 0, captureThread, stream, 0, nullptr);
    if (!stream->thread) { setError(error, errorLength, "CreateThread (capture)", HRESULT_FROM_WIN32(GetLastError())); return false; }
    stream->started = true;
    return true;
}

void cwasapi_capture_stop(CWASAPICaptureStream *stream) {
    if (!stream || !stream->started) return;
    SetEvent(stream->stopEvent);
    WaitForSingleObject(stream->thread, INFINITE);
    CloseHandle(stream->thread);
    stream->thread = nullptr;
    stream->started = false;
    stream->client->Reset();
}

void cwasapi_capture_close(CWASAPICaptureStream *stream) {
    if (!stream) return;
    cwasapi_capture_stop(stream);
    if (stream->captureClient) stream->captureClient->Release();
    if (stream->client) stream->client->Release();
    if (stream->device) stream->device->Release();
    if (stream->format) CoTaskMemFree(stream->format);
    if (stream->audioEvent) CloseHandle(stream->audioEvent);
    if (stream->stopEvent) CloseHandle(stream->stopEvent);
    delete stream;
}

// MARK: Device notifications

class DeviceNotifications : public IMMNotificationClient {
public:
    DeviceNotifications(cwasapi_device_fn fn, void *context) : fn_(fn), context_(context) {}
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs_); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&refs_);
        if (r == 0) delete this;
        return (ULONG)r;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        if (IsEqualIID(riid, __uuidof(IUnknown)) || IsEqualIID(riid, __uuidof(IMMNotificationClient))) {
            *object = static_cast<IMMNotificationClient *>(this);
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR id, DWORD state) override {
        send(state == DEVICE_STATE_ACTIVE ? CWASAPI_DEVICE_ADDED : CWASAPI_DEVICE_REMOVED, id);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR id) override { send(CWASAPI_DEVICE_ADDED, id); return S_OK; }
    HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR id) override { send(CWASAPI_DEVICE_REMOVED, id); return S_OK; }
    HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR id) override {
        if (role == eConsole && (flow == eRender || flow == eCapture)) send(flow == eRender ? CWASAPI_DEFAULT_OUTPUT_CHANGED : CWASAPI_DEFAULT_INPUT_CHANGED, id);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override { return S_OK; }
private:
    void send(int event, LPCWSTR id) {
        char buf[512];
        toUTF8(id, buf, sizeof buf);
        if (fn_) fn_(context_, event, buf);
    }
    LONG refs_ = 1;
    cwasapi_device_fn fn_;
    void *context_;
};

static std::mutex g_watchLock;
static IMMDeviceEnumerator *g_watchEnumerator = nullptr;
static DeviceNotifications *g_watchClient = nullptr;
static CO_MTA_USAGE_COOKIE g_mtaCookie = nullptr;

struct WatchRequest { cwasapi_device_fn fn; void *context; bool ok; };

// Registration runs on a thread of its own in the multithreaded apartment (kept alive by
// CoIncrementMTAUsage), so the enumerator outlives the caller's apartment, which may be the
// Win32 backend's single-threaded one.
static DWORD WINAPI watchThread(LPVOID param) {
    WatchRequest *req = static_cast<WatchRequest *>(param);
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (g_watchEnumerator && g_watchClient) {
        g_watchEnumerator->UnregisterEndpointNotificationCallback(g_watchClient);
        g_watchClient->Release();
        g_watchClient = nullptr;
    }
    req->ok = true;
    if (req->fn) {
        if (!g_watchEnumerator) g_watchEnumerator = makeEnumerator(nullptr, 0);
        if (g_watchEnumerator) {
            g_watchClient = new DeviceNotifications(req->fn, req->context);
            if (FAILED(g_watchEnumerator->RegisterEndpointNotificationCallback(g_watchClient))) {
                g_watchClient->Release();
                g_watchClient = nullptr;
                req->ok = false;
            }
        } else {
            req->ok = false;
        }
    }
    CoUninitialize();
    return 0;
}

bool cwasapi_watch_devices(cwasapi_device_fn callback, void *context) {
    std::lock_guard<std::mutex> guard(g_watchLock);
    if (!g_mtaCookie) CoIncrementMTAUsage(&g_mtaCookie);
    WatchRequest req{ callback, context, false };
    HANDLE t = CreateThread(nullptr, 0, watchThread, &req, 0, nullptr);
    if (!t) return false;
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
    return req.ok;
}
