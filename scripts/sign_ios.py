"""Sign a built iOS app on macOS; publish only an encrypted IPA artifact."""
import base64
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    for name in ('IOS_P12_BASE64', 'IOS_P12_PASSWORD', 'IOS_PROFILE_BASE64',
                 'IPA_ENCRYPTION_PASSWORD'):
        if not os.environ.get(name):
            raise RuntimeError(f'Missing secret: {name}')
    output = Path('build/ios-delivery').resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rigdeck-sign-', dir=os.environ['RUNNER_TEMP']) as work:
        work = Path(work)
        p12 = work / 'certificate.p12'
        profile_path = work / 'profile.mobileprovision'
        keychain = work / 'signing.keychain-db'
        p12.write_bytes(base64.b64decode(os.environ['IOS_P12_BASE64'], validate=True))
        profile_path.write_bytes(base64.b64decode(os.environ['IOS_PROFILE_BASE64'], validate=True))
        profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile_path), capture_output=True).stdout)
        if not profile.get('ProvisionsAllDevices'):
            raise RuntimeError('Expected enterprise profile')
        if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
            raise RuntimeError('Provisioning profile expired')
        payload = work / 'Payload'
        payload.mkdir()
        app = payload / 'Runner.app'
        shutil.copytree('build/ios/iphoneos/Runner.app', app, symlinks=True)
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        bundle = info['CFBundleIdentifier']
        allowed = profile['Entitlements']
        prefix = profile['ApplicationIdentifierPrefix'][0]
        app_id = f'{prefix}.{bundle}'
        if allowed['application-identifier'] != app_id:
            raise RuntimeError('App bundle ID does not match provisioning profile')
        if list(app.rglob('*.appex')):
            raise RuntimeError('Extensions require separate provisioning and signing')
        entitlements = {
            'application-identifier': app_id,
            'com.apple.developer.team-identifier': profile['TeamIdentifier'][0],
            'get-task-allow': False,
            'keychain-access-groups': [app_id],
        }
        if not any(group in (app_id, f'{prefix}.*') for group in allowed.get('keychain-access-groups', [])):
            raise RuntimeError('Profile does not allow app keychain group')
        entitlement_path = work / 'entitlements.plist'
        entitlement_path.write_bytes(plistlib.dumps(entitlements))
        shutil.copy2(profile_path, app / 'embedded.mobileprovision')
        password = secrets.token_urlsafe(32)
        created = False
        try:
            run('security', 'create-keychain', '-p', password, str(keychain), capture_output=True)
            created = True
            run('security', 'set-keychain-settings', '-lut', '3600', str(keychain), capture_output=True)
            run('security', 'unlock-keychain', '-p', password, str(keychain), capture_output=True)
            run('security', 'import', str(p12), '-P', os.environ['IOS_P12_PASSWORD'], '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain), capture_output=True)
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain), capture_output=True)
            identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain), capture_output=True).stdout.decode()
            hashes = re.findall(r'\) ([A-Fa-f0-9]{40}) ', identities)
            allowed_hashes = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
            identity = next((value for value in hashes if value.upper() in allowed_hashes), None)
            if not identity:
                raise RuntimeError('No valid signing identity matching profile in keychain')
            nested = list(app.rglob('*.framework')) + list(app.rglob('*.dylib'))
            for item in sorted(nested, key=lambda p: len(p.parts), reverse=True):
                run('codesign', '--force', '--sign', identity, '--keychain', str(keychain), '--timestamp=none', str(item))
            run('codesign', '--force', '--sign', identity, '--keychain', str(keychain), '--timestamp=none', '--entitlements', str(entitlement_path), str(app))
            run('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))
            signed = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', str(app), capture_output=True).stdout)
            if signed != entitlements:
                raise RuntimeError('Signed entitlements did not match requested entitlements')
            ipa = work / 'RigDeck.ipa'
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(payload), str(ipa))
            checksum = hashlib.sha256(ipa.read_bytes()).hexdigest()
            run('openssl', 'enc', '-aes-256-cbc', '-salt', '-pbkdf2', '-iter', '200000', '-md', 'sha256', '-pass', 'env:IPA_ENCRYPTION_PASSWORD', '-in', str(ipa), '-out', str(output / 'RigDeck.ipa.enc'))
            (output / 'SHA256SUMS').write_text(f'{checksum}  RigDeck.ipa\n', encoding='utf-8')
            print(f'Signature verified. Bundle ID: {bundle}; profile expires: {profile["ExpirationDate"]} UTC')
            print(f'IPA SHA256: {checksum}')
        finally:
            if created:
                run('security', 'delete-keychain', str(keychain), capture_output=True)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as exc:
        # Do not print command arguments: keychain commands contain passwords.
        print(f'{Path(exc.cmd[0]).name} failed (exit {exc.returncode})')
        if exc.stderr:
            print(exc.stderr.decode(errors='replace') if isinstance(exc.stderr, bytes) else exc.stderr)
        raise SystemExit(1)
