# Speech quality corpus

v1.95 only defines and validates the quality algorithm. No synthetic or placeholder audio is committed, so the validator reports `manifestMissing` without making a WER/CER quality claim.

For v1.96, place each real audio file in this directory and add `manifest.json`:

```json
{
  "schemaVersion": "aitrans.speech_corpus.v1",
  "corpusID": "real-device-smoke",
  "corpusVersion": "1",
  "cases": [
    {
      "id": "en-us-001",
      "audioFile": "en-us-001.m4a",
      "audioSHA256": "64 lowercase hexadecimal characters",
      "audioByteCount": 12345,
      "localeIdentifier": "en-US",
      "referenceTranscript": "The words actually spoken in the recording.",
      "sourceDescription": "User-provided real recording; quiet room."
    }
  ]
}
```

Run `python3 -B scripts/validate-speech-corpus.py --root test/speech_corpus --require-manifest` before the real-device probe. The reference transcript is used only after Apple Speech returns its final transcript. It must never be used for recognition candidate selection, prompting, correction, or production behavior.

WER is reported only for locales where whitespace tokenization is meaningful. Chinese and Japanese cases report CER without labeling character edits as WER.
