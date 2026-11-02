"""Build a small version-2 update APK for the user-authorized test device."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--gradle', required=True)
parser.add_argument('--sdk', required=True)
parser.add_argument('--java-home', required=True)
args = parser.parse_args()
root = Path(tempfile.mkdtemp(prefix='upgrade-kit-qa-fixture-'))
(root / 'settings.gradle').write_text("""
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = 'UpgradeQaFixture'
""")
(root / 'build.gradle').write_text("""
plugins { id 'com.android.application' version '8.9.1' }
android {
    namespace 'com.egeio.upgrade_kit_example'
    compileSdk 35
    defaultConfig {
        applicationId 'com.egeio.upgrade_kit_example'
        minSdk 21
        targetSdk 35
        versionCode 2
        versionName '1.1.0'
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
}
""")
(root / 'local.properties').write_text(f'sdk.dir={args.sdk}\n')
main = root / 'src/main'
java = main / 'java/com/egeio/upgrade_kit_example'
java.mkdir(parents=True)
(main / 'AndroidManifest.xml').write_text('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="upgrade_kit_example" android:theme="@android:style/Theme.Material.Light.NoActionBar">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
''')
(java / 'MainActivity.java').write_text('''
package com.egeio.upgrade_kit_example;
public class MainActivity extends android.app.Activity {
    @Override public void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        android.widget.TextView view = new android.widget.TextView(this);
        view.setText("Upgrade QA fixture installed: versionCode=2, versionName=1.1.0");
        view.setTextSize(20);
        view.setPadding(32, 96, 32, 32);
        setContentView(view);
    }
}
''')
assets = main / 'assets'
assets.mkdir()
(assets / 'qa-payload.bin').write_bytes(os.urandom(256 * 1024))
env = dict(os.environ, JAVA_HOME=args.java_home)
log = root / 'build.log'
with log.open('w') as output:
    completed = subprocess.run([args.gradle, '--offline', 'assembleDebug', '--console=plain'], cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
if completed.returncode:
    raise SystemExit(log.read_text())
apk = root / 'build/outputs/apk/debug/UpgradeQaFixture-debug.apk'
print(json.dumps({'apk': str(apk), 'build_log': str(log), 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'size': apk.stat().st_size}))
