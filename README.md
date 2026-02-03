# PomumD

[Wyoming Protocol](https://github.com/OHF-Voice/wyoming) text-to-speech (TTS) and speech-to-text (STT) server using iOS AVFoundation and Speech frameworks.

Runs on iOS/iPadOS 16.0+, macOS 11.0+, and visionOS 1.0+ devices.

## Text-to-Speech

[AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) of AVFoundation framework.

> Keep in mind that although Siri voices are available to be selected in Spoken Content Settings, they are not available through the AVSpeechSynthesizer API.
> (https://developer.apple.com/videos/play/wwdc2020/10022/?time=213)

## Speech-to-Text

- For iOS/iPadOS/macOS/visionOS 26.0+: [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) of Speech framework.
- For others: [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer).

## Screenshot

<img src="assets/screenshot.png" alt="screenshot" width=50%>
