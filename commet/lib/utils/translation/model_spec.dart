/// Firefox Translations models (Bergamot / Marian), one per direction to or
/// from English. The generated catalog in models.dart pins every
/// file by size and SHA-256, so a model can't change under us.
library;

/// Which builds of Firefox ship a model; for some directions Android gets a
/// smaller one.
enum ModelPlatforms { all, desktop, android }

enum ModelFileType { model, lex, vocab, srcvocab, trgvocab }

class F {
  const F(this.type, this.name, this.blob, this.bytes, this.sha256);

  const F.model(String name, String blob, int bytes, String sha256)
      : this(ModelFileType.model, name, blob, bytes, sha256);
  const F.lex(String name, String blob, int bytes, String sha256)
      : this(ModelFileType.lex, name, blob, bytes, sha256);
  const F.vocab(String name, String blob, int bytes, String sha256)
      : this(ModelFileType.vocab, name, blob, bytes, sha256);
  const F.srcvocab(String name, String blob, int bytes, String sha256)
      : this(ModelFileType.srcvocab, name, blob, bytes, sha256);
  const F.trgvocab(String name, String blob, int bytes, String sha256)
      : this(ModelFileType.trgvocab, name, blob, bytes, sha256);

  final ModelFileType type;

  /// The file name Firefox gives it, e.g. model.enes.intgemm.alphas.bin.
  final String name;

  /// The attachment's name on Mozilla's CDN.
  final String blob;
  final int bytes;
  final String sha256;

  static const cdn =
      "https://firefox-settings-attachments.cdn.mozilla.net/main-workspace/translations-models/";

  Uri get url => Uri.parse("$cdn$blob");
}

class TranslationModelSpec {
  const TranslationModelSpec(
      this.from, this.to, this.version, this.platforms, this.files);

  final String from;
  final String to;
  final String version;
  final ModelPlatforms platforms;
  final List<F> files;

  /// "es-en"
  String get key => "$from-$to";

  /// Directory name on disk; a new version gets a new directory.
  String get directory => "$key-$version";

  int get bytes => files.fold(0, (sum, f) => sum + f.bytes);

  F? file(ModelFileType type) {
    for (final f in files) {
      if (f.type == type) return f;
    }
    return null;
  }

  /// Marian options for this model, as Firefox Translations runs it (one
  /// best guess per word, no beam search, int8 matrix maths), with the files
  /// in [dir].
  String config(String dir) {
    String path(ModelFileType t) => "$dir/${file(t)!.name}";
    final shared = file(ModelFileType.vocab) != null;
    final src = path(shared ? ModelFileType.vocab : ModelFileType.srcvocab);
    final trg = path(shared ? ModelFileType.vocab : ModelFileType.trgvocab);
    return """
models:
  - ${_quote(path(ModelFileType.model))}
vocabs:
  - ${_quote(src)}
  - ${_quote(trg)}
shortlist:
  - ${_quote(path(ModelFileType.lex))}
  - false
beam-size: 1
normalize: 1.0
word-penalty: 0
max-length-break: 128
mini-batch-words: 1024
workspace: 128
max-length-factor: 2.0
skip-cost: true
cpu-threads: 0
quiet: true
quiet-translation: true
gemm-precision: int8shiftAlphaAll
alignment: soft
""";
  }

  static String _quote(String s) =>
      "'${s.replaceAll("'", "''")}'"; // YAML single-quoted scalar
}

/// English names of the languages the catalog covers, by Firefox's codes.
const translationLanguageNames = <String, String>{
  "af": "Afrikaans",
  "ar": "Arabic",
  "az": "Azerbaijani",
  "be": "Belarusian",
  "bg": "Bulgarian",
  "bn": "Bengali",
  "bs": "Bosnian",
  "ca": "Catalan",
  "cs": "Czech",
  "da": "Danish",
  "de": "German",
  "el": "Greek",
  "en": "English",
  "es": "Spanish",
  "et": "Estonian",
  "eu": "Basque",
  "fa": "Persian",
  "fi": "Finnish",
  "fr": "French",
  "gl": "Galician",
  "gu": "Gujarati",
  "he": "Hebrew",
  "hi": "Hindi",
  "hr": "Croatian",
  "hu": "Hungarian",
  "id": "Indonesian",
  "is": "Icelandic",
  "it": "Italian",
  "ja": "Japanese",
  "kn": "Kannada",
  "ko": "Korean",
  "lt": "Lithuanian",
  "lv": "Latvian",
  "ml": "Malayalam",
  "mr": "Marathi",
  "ms": "Malay",
  "nb": "Norwegian Bokmål",
  "nl": "Dutch",
  "pl": "Polish",
  "pt": "Portuguese",
  "ro": "Romanian",
  "ru": "Russian",
  "sk": "Slovak",
  "sl": "Slovenian",
  "sq": "Albanian",
  "sr": "Serbian",
  "sv": "Swedish",
  "ta": "Tamil",
  "te": "Telugu",
  "th": "Thai",
  "tl": "Tagalog",
  "tr": "Turkish",
  "ug": "Uyghur",
  "uk": "Ukrainian",
  "ur": "Urdu",
  "vi": "Vietnamese",
  "zh-Hans": "Chinese (Simplified)",
  "zh-Hant": "Chinese (Traditional)",
};

String translationLanguageName(String code) =>
    translationLanguageNames[code] ?? code;
