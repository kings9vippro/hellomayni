import pathlib, plistlib, zipfile, sys, struct
ipa=pathlib.Path(sys.argv[1]); expected=sys.argv[2]
with zipfile.ZipFile(ipa) as z:
    assert z.testzip() is None
    roots={p.split("/")[1] for p in z.namelist() if p.startswith("Payload/") and len(p.split("/"))>2 and p.split("/")[1].endswith(".app")}
    assert len(roots)==1, roots
    root="Payload/"+next(iter(roots))+"/"
    info=plistlib.loads(z.read(root+"Info.plist"))
    for k in ("CFBundleIdentifier","CFBundleExecutable","CFBundlePackageType","CFBundleShortVersionString","CFBundleVersion","MinimumOSVersion"):
        assert info.get(k) and "$(" not in str(info[k]), (k,info.get(k))
    assert info["CFBundleIdentifier"]==expected
    assert info["CFBundlePackageType"]=="APPL"
    assert info["CFBundleShortVersionString"]=="10.0.0"
    assert tuple(map(int,info["MinimumOSVersion"].split("."))) <= (18,7,2)
    assert 1 in info.get("UIDeviceFamily",[]), info.get("UIDeviceFamily")
    assert info.get("CFBundleSupportedPlatforms")==["iPhoneOS"]
    binary=z.read(root+info["CFBundleExecutable"])
    magic,cpu,subtype,ftype=struct.unpack_from("<IIII",binary)
    assert magic==0xfeedfacf and cpu==0x0100000c and ftype==2,(hex(magic),hex(cpu),ftype)
    assert not any(".appex/" in x for x in z.namelist())
    assert "audio" in info.get("UIBackgroundModes",[])
    assert ("fetch" in info.get("UIBackgroundModes",[]))==(expected=="com.touchlab.optimizer")
    print("IPA verified:",ipa.name,expected,info["CFBundleShortVersionString"],"min iOS",info["MinimumOSVersion"],"ARM64")
