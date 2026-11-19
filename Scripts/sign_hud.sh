#!/bin/bash
# macOS, using a valid signing identity already imported in your keychain.
set -euo pipefail
if [ "$#" -ne 5 ]; then
  echo "Usage: bash sign_hud.sh unsigned.ipa host.mobileprovision extension.mobileprovision 'CERT_SHA1' output.ipa" >&2
  exit 64
fi
python3 - "$@" <<'PY'
import datetime,hashlib,pathlib,plistlib,subprocess,sys,tempfile
ipa,hostprofile,extprofile,identity,output=sys.argv[1:]
group="group.com.touchlab.optimizer.hud"
identity=identity.replace(" ","").upper()
if len(identity)!=40 or any(c not in "0123456789ABCDEF" for c in identity):
    raise SystemExit("Use certificate SHA-1 from security find-identity -v -p codesigning")
output=str(pathlib.Path(output).resolve())
if pathlib.Path(output).exists():
    raise SystemExit("Output already exists")
def run(*args):
    subprocess.run(args,check=True)
def entitlements(profile,bundle):
    p=plistlib.loads(subprocess.check_output(["security","cms","-D","-i",profile]))
    e=p["Entitlements"]; team=p["TeamIdentifier"][0]
    if p["ExpirationDate"]<=datetime.datetime.utcnow(): raise SystemExit("Expired profile: "+bundle)
    if e.get("application-identifier")!=team+"."+bundle: raise SystemExit("Profile does not match "+bundle)
    if group not in e.get("com.apple.security.application-groups",[]): raise SystemExit("Profile does not grant App Groups: "+bundle)
    if identity not in [hashlib.sha1(c).hexdigest().upper() for c in p.get("DeveloperCertificates",[])]: raise SystemExit("Certificate not present in profile: "+bundle)
    if not p.get("ProvisionedDevices") and not p.get("ProvisionsAllDevices"): raise SystemExit("Not a device-installable development/ad hoc/enterprise profile: "+bundle)
    allowed={k:e[k] for k in ("application-identifier","com.apple.developer.team-identifier","get-task-allow") if k in e}
    allowed["com.apple.security.application-groups"]=[group]
    return p,team,allowed
with tempfile.TemporaryDirectory(prefix="touchlab-sign-") as tmp:
    root=pathlib.Path(tmp)
    run("ditto","-x","-k",str(pathlib.Path(ipa).resolve()),tmp)
    app=root/"Payload/TouchLabHUD.app"; ext=app/"PlugIns/FPSBroadcast.appex"
    def bundle(path):return plistlib.loads((path/"Info.plist").read_bytes())["CFBundleIdentifier"]
    host,team,he=entitlements(hostprofile,bundle(app));plugin,other,ee=entitlements(extprofile,bundle(ext))
    if team!=other:raise SystemExit("Host and extension must use the same team")
    if host.get("ProvisionedDevices") and plugin.get("ProvisionedDevices") and not set(host["ProvisionedDevices"])&set(plugin["ProvisionedDevices"]):raise SystemExit("Profiles do not share any authorized devices")
    for path,profile,e,name in [(ext,extprofile,ee,"extension"),(app,hostprofile,he,"host")]:
        import shutil
        shutil.copyfile(profile,path/"embedded.mobileprovision")
        ep=root/(name+".plist");ep.write_bytes(plistlib.dumps(e))
        for framework in sorted((path/"Frameworks").glob("*.framework")) if (path/"Frameworks").exists() else []:
            run("codesign","--force","--sign",identity,str(framework))
        run("codesign","--force","--sign",identity,"--entitlements",str(ep),"--generate-entitlement-der",str(path))
        run("codesign","--verify","--strict",str(path))
    run("codesign","--verify","--deep","--strict",str(app))
    run("ditto","-c","-k","--keepParent",str(root/"Payload"),output)
    print("Signed IPA:",output,". The device must also be provisioned and trust the certificate.")
PY
