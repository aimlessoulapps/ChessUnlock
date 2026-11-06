"""Run the pure Kotlin watcher regression checks without adding test dependencies."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
# Flutter's Android build populates these compiler dependencies.
jars = []
for group in ('org.jetbrains.kotlin', 'org.jetbrains.kotlinx', 'org.jetbrains',
              'org.jetbrains.intellij.deps'):
    folder = cache / group
    if folder.exists():
        for artifact in folder.iterdir():
            versions = sorted(artifact.iterdir(), key=lambda p: tuple(
                int(n) if n.isdigit() else 0 for n in p.name.split('.')), reverse=True)
            if versions:
                jars.extend(versions[0].rglob('*.jar'))
if not any('kotlin-compiler-embeddable-' in p.name for p in jars):
    raise SystemExit('Run the Android Gradle build first to cache the Kotlin compiler.')
java_home = Path(os.environ.get('JAVA_HOME', '/Applications/Android Studio.app/Contents/jbr/Contents/Home'))
java = str(java_home / 'bin/java')
classpath = os.pathsep.join(map(str, jars))
with tempfile.TemporaryDirectory(prefix='chessunlock-kotlin-') as output:
    subprocess.run([java, '-cp', classpath, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-classpath', classpath, '-d', output,
                    str(root / 'android/app/src/main/kotlin/com/aimlessoul/chessunlock/ForegroundAppState.kt'),
                    str(root / 'android/app/src/test/kotlin/com/aimlessoul/chessunlock/ForegroundAppStateTest.kt')], check=True)
    subprocess.run([java, '-cp', output + os.pathsep + classpath,
                    'com.aimlessoul.chessunlock.ForegroundAppStateTestKt'], check=True)
