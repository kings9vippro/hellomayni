import pathlib, plistlib, sys, zipfile, struct
with zipfile.ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None
    root="Payload/TouchLabHUD.app/"
    ext=root+"PlugIns/FPSBroadcast.appex/"
    host=plistlib.loads(z.read(root+"Info.plist"))
    plugin=plistlib.loads(z.read(ext+"Info.plist"))
    assert host["CFBundleIdentifier"]=="com.touchlab.optimizer.hud"
    assert plugin["CFBundleIdentifier"]==host["CFBundleIdentifier"]+".broadcast"
    assert host["CFBundleShortVersionString"]==plugin["CFBundleShortVersionString"]=="10.0.0"
    assert host["CFBundleVersion"]==plugin["CFBundleVersion"]
    assert "audio" in host["UIBackgroundModes"]
    assert plugin["NSExtension"]["NSExtensionPointIdentifier"]=="com.apple.broadcast-services-upload"
    for prefix,info in [(root,host),(ext,plugin)]:
        assert tuple(map(int,info["MinimumOSVersion"].split(".")))<=(18,7,2)
        magic,cpu,_,kind=struct.unpack_from("<IIII",z.read(prefix+info["CFBundleExecutable"]))
        assert (magic,cpu,kind)==(0xfeedfacf,0x0100000c,2)
    print("Host and embedded ReplayKit extension package validated, unsigned.")
