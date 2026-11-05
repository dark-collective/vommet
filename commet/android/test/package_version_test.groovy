// Vommet: run with Groovy (no Android SDK or Flutter build required):
// java -cp /path/to/groovy.jar groovy.ui.GroovyMain \
//   commet/android/test/package_version_test.groovy [path/to/app/build.gradle]
// Executes the actual Gradle version configuration with only project properties
// stubbed. Stop before signing/Android plugins, which need the Android toolchain.
def gradleFile = new File(args ? args[0] : 'commet/android/app/build.gradle')
def source = gradleFile.text
def configuration = source.substring(source.indexOf('def localProperties ='),
        source.indexOf('def keystoreProperties ='))
assert source.contains('versionName flutterVersionName')
assert source.contains('versionCode flutterVersionCode.toInteger()')
def directory = File.createTempDir('vommet-package-version-', '')
try {
    def propertiesFile = new File(directory, 'local.properties')
    def evaluateVersion = { String label, String name, String code ->
        propertiesFile.text = "flutter.versionName=$name\nflutter.versionCode=$code\n"
        def defines = ['PLATFORM=android', "VERSION_TAG=$label", 'BUILD_DETAIL=ci']
                .collect { it.getBytes('UTF-8').encodeBase64().toString() }.join(',')
        def binding = new Binding([
                rootProject: [file: { String path -> new File(directory, path) }],
                project: [findProperty: { String key -> key == 'dart-defines' ? defines : null }],
        ])
        new GroovyShell(binding).evaluate(configuration + '\n[flutterVersionName, flutterVersionCode]')
    }
    // Actual published 05b/05c build numbers; the first release and a date
    // rollover exercise the existing release-name grammar too.
    def failures = []
    for (def example : [
            ['testing-2026-11-05b (185)', 'testing-2026-11-05b', '443854'],
            ['testing-2026-11-05c (186)', 'testing-2026-11-05c', '444620'],
            ['testing-2026-11-05 (184)', 'testing-2026-11-05', '443000'],
            ['testing-2026-11-06', 'testing-2026-11-06', '445000'],
    ]) {
        def actual = evaluateVersion(example[0], '0.5.1', example[2])
        def expected = [example[1], example[2]]
        if (actual != expected) {
            failures << "${example[0]}: expected $expected, got $actual"
        }
        println "${example[0]}: versionName=${actual[0]}, Flutter build number=${actual[1]} (arm64 versionCode=${actual[1].toInteger() + 2000})"
        // Optional real binary-manifest packaging probe. This is a metadata
        // fixture, not a signed app rebuild. Both tools must be supplied.
        def aapt2 = System.getenv('AAPT2')
        def framework = System.getenv('ANDROID_FRAMEWORK_JAR')
        assert (aapt2 != null) == (framework != null)
        if (aapt2) {
            def manifest = new File(directory, 'AndroidManifest.xml')
            manifest.text = '<manifest package="im.nether.chat"><application /></manifest>'
            def apk = new File(directory, 'metadata.apk')
            def code = (actual[1].toInteger() + 2000).toString()
            def link = new ProcessBuilder(aapt2, 'link', '-I', framework,
                    '--manifest', manifest.path, '--version-code', code,
                    '--version-name', actual[0], '-o', apk.path)
                    .redirectErrorStream(true).start()
            def linkOutput = link.inputStream.text
            assert link.waitFor() == 0 : linkOutput
            def dump = new ProcessBuilder(aapt2, 'dump', 'badging', apk.path)
                    .redirectErrorStream(true).start()
            def badging = dump.inputStream.text
            assert dump.waitFor() == 0 : badging
            assert badging.contains("name='im.nether.chat' versionCode='$code' versionName='${actual[0]}'")
            println "Binary manifest fixture: ${badging.readLines()[0]}"
        }
    }
    // Existing release/local/fallback naming contracts are unchanged.
    for (def label : ['development', 'main.186', 'v0.5.2', '', 'testing-2026-11-05c-extra']) {
        assert evaluateVersion(label, '0.5.2', '1014') == ['0.5.2', '1014']
    }
    propertiesFile.delete()
    def noDefines = new Binding([
            rootProject: [file: { String path -> new File(directory, path) }],
            project: [findProperty: { String key -> null }],
    ])
    assert new GroovyShell(noDefines).evaluate(configuration + '\n[flutterVersionName, flutterVersionCode]') == ['1.0', '1']
    assert failures.empty : failures.join('\n')
    println 'PASS: tester package names, unchanged versionCode, release/local names and missing properties'
} finally {
    directory.deleteDir()
}
