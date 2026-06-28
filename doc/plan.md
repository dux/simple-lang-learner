# lang-bar - planning

A macOS menu-bar language learner.
Think "LingoBar, but better": local-LLM driven, with real listening (STT) and speaking (TTS) practice and pronunciation feedback.

Status: planning. Nothing built yet. This doc is the working plan.

## 1. Vision

A menu-bar app that rotates a target-language word on a timer (like LingoBar), but goes much further:

* Local LLMs do the language work (examples, grammar, translation, adaptive selection, conversation).
* It speaks to you (TTS): on a new word it says the word in the target language, then what it means in English.
* It listens to you (STT via whisper): you speak the word or a sentence, it checks your pronunciation, tells you what you missed, and says it back the right way.

Everything runs locally. No account, no cloud, privacy-first (matching LingoBar's stance, then beating it on capability).

## 2. Shared whisper model reuse (verified)

Goal: do not download the same 1.6 GB model twice when OpenSuperWhisper is already installed.

What we verified on this machine:

* App: `/Applications/OpenSuperWhisper.app`, bundle id `ru.starmel.OpenSuperWhisper`.
* Model file: `~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin`
  * Size: 1,624,555,275 bytes (~1.6 GB).
  * Magic bytes: `0x67676d6c` ("ggml") - a standard whisper.cpp model, large-v3-turbo.
  * Readable by our user (mode 600, same user).
  * Pure ggml/Metal: no CoreML sidecar (`encoder.mlmodelc`) present; app ships `libomp.dylib` for CPU threads.
* OpenSuperWhisper is **not sandboxed at runtime**: no `~/Library/Containers/ru.starmel.OpenSuperWhisper` exists, and it writes to the real `~/Library/Application Support`. So the path above is stable and directly reachable.
* Any whisper.cpp build (e.g. SwiftWhisper, or whisper.cpp directly) can load this `.bin` as-is.

Other transcription apps also present (different/incompatible formats, ignore for sharing):

* `com.superduper.superwhisper` - commercial superwhisper, CoreML/argmax format (not whisper.cpp compatible).
* `com.carelesswhisper.app`, `nonotoday.SRTWhisper` - sandboxed containers.

### Even simpler: the model is already in a shared cache we can reuse directly

* `~/.cache/whisper-models/ggml-large-v3-turbo.bin` already exists (1,624,555,275 bytes, byte-identical size to OpenSuperWhisper's copy).
* This cache is shared by the user's `srt` recipe and the `swift-learn-lang` reference app (`WhisperModels.modelsDir = ~/.cache/whisper-models`).
* So STT needs no download at all: lang-bar reuses `~/.cache/whisper-models` the same way the reference does.
* STT engine is the `whisper-cli` binary (brew `whisper-cpp`, installed at `/opt/homebrew/bin/whisper-cli`), not the SwiftWhisper library. The reference's `Transcriber.swift` already shells out to it.

### Reuse strategy: `ModelResolver`

Resolve at runtime, do not hardcode one path:

1. Use `~/.cache/whisper-models/ggml-<name>.bin` if present (already populated, shared with `srt` and the reference). This is also our own model dir and download target, so reuse is automatic and needs no copy.
2. Else fall back to OpenSuperWhisper's `~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/`: validate the `ggml` magic, then **hardlink** it into `~/.cache/whisper-models/`.
   * Same APFS volume + same user means the hardlink shares disk blocks: no second 1.6 GB on disk, not just no second download.
   * The inode survives even if OpenSuperWhisper later deletes its copy. Symlink fallback if the source is on a different volume. Treat the source strictly read-only.
3. Else download into `~/.cache/whisper-models/` (the reference's existing logic), so the app still works on a clean machine.

### Sandbox caveat (a real decision)

* Direct distribution (.dmg, notarized, not sandboxed): read the shared path directly, zero friction. Recommended for a power-user menu-bar tool.
* Mac App Store (sandboxed): cannot read another app's Application Support without a user-picked security-scoped bookmark (a one-time "locate the model" file picker). Doable, but adds friction and rules out the silent hardlink approach.

## 3. LingoBar baseline (what we are beating)

Source: https://lingobar.net/ and App Store listing. Captured for reference.

* macOS 14+ native menu-bar app, App Store, free, no account, no Dock icon.
* Drag with Cmd to position in the menu bar; launches at login.
* Rotates words every 1 / 5 / 10 / 30 / 60 / 90 minutes.
* "Spaced repetition" via passive active-recall: see foreign word, recall, then reveal translation. No notifications, streaks, or guilt.
* ~1,500 built-in words across 23 categories; up to 200 personal words; hide mastered words; star/favorite words.
* 12 languages: Spanish, English, German, French, Italian, Portuguese, Polish, Swedish, Hungarian, Russian, Arabic, Korean. Any source/target pair. RTL support (Arabic).
* Word presentation: translation + example sentences in both languages; gender/article shown (der/die/das, Spanish gender); audio pronunciation of words and sentences using system voices.
* Click word -> popover with full translation; sound button to hear it.
* Progress tracked per language pair; optional iCloud sync; zero tracking, zero ads.

What LingoBar does NOT have (our opening):

* No AI/LLM. Fixed word list, fixed example sentences.
* No speaking practice, no pronunciation feedback. Listening is one-way (it speaks, you do not).
* No conversation or generative content.

## 4. What "better" means - our differentiators

1. **Local CLI agent as the LLM engine** (Claude Code / Codex / opencode, headless):
   * Generate fresh, varied example sentences per word and per difficulty, instead of a fixed DB.
   * On-demand grammar: gender, article, plural, conjugation, etymology, register, false-friend warnings.
   * Translate arbitrary text / clipboard, both directions.
   * Adaptive selection: pick the next word from what you struggle with, not just a timer.
   * Conversation mode: short chats in the target language with corrections.
2. **Two-way speech**:
   * TTS: speak the word in target language, then its English meaning, on each rotation.
   * STT (whisper, reusing the shared model): you speak; it transcribes.
3. **Pronunciation feedback loop**:
   * You speak the word/sentence -> whisper transcribes -> compare to target -> LLM explains what you missed -> TTS says it the right way.

## 5. The interaction flow (as requested)

### Word advancing

* MVP (windowed app): a **"Next random word"** button advances to a random word on demand. This is the primary control for now.
* Timed automatic rotation (LingoBar's every-N-minutes model) and a menu-bar presence are out of scope; advancing is manual via the button.
* On a new word (manual or timed): TTS says the word in the target language, then says what it is in English.
  * Make this configurable/mutable (could be noisy); allow "speak on new word: off / word only / word + meaning".

### Word detail view (main window now, popover later)

* Show the word (with article/gender/plural) and its English meaning, with play + mic buttons.
* Example usages (LLM-generated, a few): each sentence has
  * three speed buttons (normal / slow / super-slow) to hear it in the original language, and a mic button to practice it,
  * a segmented gloss below it (each original-language chunk followed by its meaning in parentheses, in original word order; chunks shown in primary and tappable to hear just that chunk, meanings muted/italic and not tappable). No separate translated sentence, no speak button on the gloss.
* Speaking practice: tap a word or sentence mic (or hold left Command).
  * Whisper transcribes what you said.
  * The app matches it against that specific example, shows what was heard + what you missed, and plays the example back correctly via TTS.
* Quick actions: star/favorite, mark as known/hide, "explain grammar", "give me another example", "next word now".

## 6. Pronunciation scoring - approach

Two tiers, ship the pragmatic one first:

* MVP: whisper transcribes the user's audio; compare transcript to target text (normalized + phonetic distance); hand transcript + target to the LLM to produce a short "what you missed" explanation; TTS plays the correct version.
  * Caveat: whisper is forgiving and not built for phoneme-level scoring; it tells you "did the word come through", not fine accent detail.
* Later: phoneme-level forced alignment / a dedicated pronunciation model for real per-sound scoring. More work; revisit after MVP.

## 7. Decisions locked (from review)

* Distribution: direct .dmg, notarized, **not sandboxed**. Enables silent model reuse (hardlink) per section 2.
* LLM engine: a **local CLI agent run headless**, not a server/embedded model. All three are installed: `claude` 2.1.195, `codex` 0.139.0, `opencode` 1.16.2. (`llm` on PATH is the user's memory tool, not for generation.)
* TTS: **Apple premium/Siri voices via `AVSpeechSynthesizer`** (on-device neural for major languages). Reuse the reference's `Speaker.swift` best-voice logic. Zero dependency, no bundling.
* First language pair: **Spanish -> English**.
* App identity: display name **Friendly Lang Tutor**, `APP_NAME`/binary/bundle `FriendlyLangTutor`, bundle id `com.dux.friendly-lang-tutor`, installs to `/Applications/FriendlyLangTutor.app`. No collision with the reference's `DuxLangLearner.app`. Cache dir `~/Library/Caches/com.dux.friendly-lang-tutor/`.
* Word/sentence content: **generated once per word, then cached**, with re-generate style variants. See section 9.
* Machine: Apple M4 Pro (arm64), 184 system voices available.

## 8. Tech stack

* UI: Swift + SwiftUI **windowed app** (`WindowGroup` + `Settings` scene, like the reference). A menu-bar/status-item ("toolbar") presence is out of scope.
* STT: shell out to the `whisper-cli` binary (brew `whisper-cpp`, already installed), model from `~/.cache/whisper-models` per section 2. Lift the reference's `Transcriber.swift` (record 16 kHz mono WAV, run `whisper-cli -m model -l lang`, push-to-talk on holding left Command).
* LLM: lift the reference's `ChatBackend.swift` near-wholesale. It already ships adapters for `claude`, `codex`, `opencode`, and `ollama`, each with `isAvailable()`, `resolve()` (finds CLIs in `~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin` because the GUI launch PATH is minimal), and a one-shot `complete(prompt)`.
  * For word generation we want stateless one-shots, so use `complete(prompt)` with a strict-JSON prompt; no session/coach plumbing needed.
  * Default adapter `claude` (plain `claude -p "<prompt>"` -> reply text on stdout). Note: this CLI version's `--output-format json` emits a JSON *array of stream events*, not a single `{result}` object, so we use plain `-p` and read stdout (stdin is the null device so `-p` does not stall). `codex`/`opencode` selectable in settings.
* TTS: `AVSpeechSynthesizer`, best premium/Siri voice per language (reuse `Speaker.swift`). To honor "pre-generate audio before showing the word" (section 9), render via the `AVSpeechSynthesizer.write(_:toBufferCallback:)` API into cached files and play with `AVAudioPlayer`. Caveat: some premium/personal voices refuse the write API and yield no buffers; fall back to live `speak()` (uncached) for those. Keep a `TTSEngine` protocol so a bundled engine (Piper/Kokoro) can be added later without touching callers.
* Storage: SQLite via GRDB for words, progress, favorites, and SRS state. Generated content + audio live in a separate disposable cache (section 9).
* Distribution: direct, notarized, hardened runtime, not sandboxed.

## 9. Per-word generation + caching pipeline (core design)

Driven by the user's spec: every word is generated once, cached, with regenerate-by-style, and audio for the target-language sentences is pre-rendered before the word is shown.

Content shape per `(language pair, word, style)`:

* The word, with article/gender/plural where relevant, and its English meaning.
* Exactly 3 example sentences. Each has: the target-language ("non-native") sentence, and a segmented gloss (the sentence broken into chunks, each chunk followed by its native-language meaning in parentheses, in original word order). No standalone translated sentence.
* Audio only for the 3 target-language sentences. The gloss is text-only - no native audio.

Audio is cached as **whole sentences**, not word-by-word: natural prosody needs whole-sentence synthesis, and Spanish blends vowels across word boundaries (synalepha), so concatenating per-word clips sounds wrong. What we cache:

* The headword spoken alone - pre-rendered before the word is shown; reusable, cache once per `(word, voice, rate)`.
* Each of the 3 target sentences spoken whole - rendered lazily on first play; not reusable, cache per `(word, style, sentenceIndex, rate)`.

Content format: **flat line format**, not JSON or YAML. One `KEY value` per line, values are single-line, no escaping, no indentation. `ES`/`EN` lines pair up in order: `ES` is the target sentence, `EN` is its segmented gloss. Parser = split lines, first token is the key. The LLM emits this directly and the cache stores it verbatim.

```
WORD comer
POS verb
ARTICLE -
MEANING to eat
ES Vamos a comer juntos esta noche.
EN Vamos a comer (let's eat) juntos (together) esta noche (tonight)
ES ¿A qué hora quieres comer?
EN A qué hora (at what time) quieres (do you want) comer (to eat)
ES Siempre como fruta por la mañana.
EN Siempre (always) como (I eat) fruta (fruit) por la mañana (in the morning)
```

Seed word lists are plain text too: one word per line (`seeds/es.txt`).

Styles (regenerate options), ordered low -> high:

* `basic` - shortest, beginner-friendly, high-frequency words only.
* `everyday` - neutral, common usage. Default.
* `fun` - casual, playful, light slang.
* `formal` - polite/business register.
* `expert` - advanced, idiomatic, native-level vocabulary and structure.

Regenerate produces a fresh variant in the chosen style and caches it under that style key. A word can hold multiple cached style variants.

Selection flow (the ordering the user asked for):

1. Pick the next word (seed list / SRS queue).
2. If text for `(pair, word, style)` is not cached: call the LLM adapter, parse the flat line format (word meta + 3 sentence pairs), cache the raw text.
3. Pre-render TTS audio for the headword only, cache it, then show the word right away (no waiting on sentence audio).
4. Target sentence audio renders lazily on first play and is then cached. The gloss has no audio.

Cache layout (disposable, OS/user-cleanable):

* Location: `~/Library/Caches/<bundle-id>/` (standard macOS cache; safe to purge, regenerable). Honors the user's "cache folder or tmp that can be picked up for cleaning".
* `text/<pair>/<wordHash>/<style>.txt` - generated content (flat line format).
* `audio/<pair>/<wordHash>/word.<voice>.<ratePct>.caf` - headword spoken alone (reusable across styles).
* `audio/<pair>/<wordHash>/<style>/<sentenceIndex>.<lang>.<ratePct>.caf` - rendered target-sentence speech (`<lang>` is always the target).
* A "Clear cache" action + cache-size display in settings.
* Audio format: `.caf` from the AVSpeech write API; consider AAC/.m4a transcode later to shrink the cache.

## 10. Resolved + remaining

Resolved:

* Speech speed: a baseline in Settings (50%-150% in 2% steps; 1.0 = system default), plus per-item playback buttons - normal / slow (0.7x) / super slow (0.5x) - that scale off the baseline. Applies to live speech and rendered audio; audio cache is keyed by rate so each speed caches separately.
* TTS: Apple premium/Siri voices via `AVSpeechSynthesizer` (reuse `Speaker.swift`).
* First language pair: Spanish -> English.
* Default CLI agent: `claude` (others selectable).

Remaining (low-stakes, will default unless told otherwise):

* Pronunciation scoring: ship whisper-transcribe + LLM "what you missed" first; defer phoneme-level scoring (section 6).
* Style labels: `everyday` / `fun` / `formal` (default; trivial to rename).

## 11. Suggested MVP scope

A **windowed Swift app** that already beats LingoBar on the axes the user cares about:

* A main window showing the current word, with a **"Next random word"** button.
* TTS on new word: speak the word in the target language, then its English meaning (configurable: off / word only / word + meaning).
* Per-word generation pipeline with caching and the 3 cached example sentences (section 9).
* Word detail: word meta + the 3 example sentences, each playable in the target language, with a segmented gloss (chunks + meanings in parentheses) below it.
* Record + pronunciation check on the word or any example sentence (per-item mic, or hold ⌘): transcribe via `whisper-cli` + the shared model, match against that example, "what you missed", play it back correctly.
* Whisper model reuse from `~/.cache/whisper-models` (already present; OpenSuperWhisper hardlink + download as fallbacks).
* One CLI-agent LLM backend (`claude`), one neural TTS engine, one or two language pairs to prove the loop.
* `Hammerfile` for build/install/run/dev, mirroring the reference.

## 12. Reuse from swift-learn-lang (reference)

Reference: `../swift-learn-lang`. It is a different product (conversation/scenario roleplay tutor), but its infrastructure is exactly what we need. Lift these, build the vocab product on top:

* `ChatBackend.swift` - CLI-agent LLM adapters (claude/codex/opencode/ollama). Use `complete(prompt)` for stateless word generation. Reuse as-is, add our JSON word schema.
* `Transcriber.swift` - mic record + `whisper-cli` shell-out + push-to-talk. Reuse as-is.
* `WhisperModels.swift` - `~/.cache/whisper-models` catalog/paths/download. Extend `ModelResolver` to also hardlink OpenSuperWhisper's copy when the cache is empty.
* `Speaker.swift` - AVSpeechSynthesizer best-voice TTS. This is the reference's TTS; it is decent (premium/enhanced voices) but is the *system* path, not the neural engine the user asked for. Keep it as the fallback engine behind the `TTSEngine` protocol; the chosen neural engine (section 10) is the primary.
* `Package.swift` (swift-tools 6.0, macOS 14, executable target at `app/`) and `Info.plist` - copy the shape.
* `Languages.swift`, `AppSettings.swift`, `SettingsView.swift` - copy and trim to our needs.

New code we write: word model + seed lists, the generation/caching pipeline (section 9), the word UI (current word, 3 sentences, next-random button), pronunciation-feedback glue.

## 13. Build/run via Hammerfile + staged plan

Task running is via `hammer` (`~/bin/hammer`), one `Hammerfile` per the reference. Planned tasks (same names as the reference so muscle memory carries over):

* `doctor` - check `swift`, `codesign`, `whisper-cli`, and at least one CLI agent are present.
* `build` / `release` - `swift build [-c release]`.
* `app` - assemble the `.app` bundle, ad-hoc codesign.
* `install` - build bundle, copy to `/Applications`.
* `run` - open the installed app.
* `dev` - install + run, watch `app/`, reinstall on change (7s throttle).
* `clean`, `lint`, `test`.

Staged delivery:

1. Stage 1 (now): windowed Swift app, "Next random word", generation + cache, 3 sentences with audio, pronunciation check.
2. Stage 2 (later): SRS from pronunciation results, extra modes (conversation, clipboard translate, minimal pairs).

The app stays a windowed app. A menu-bar/status-item presence with timed word rotation is out of scope, not a planned stage.
