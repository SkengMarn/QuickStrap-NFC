# Quick Start Guide

Get your NFC Event Management app up and running in 5 minutes!

## 🚀 5-Minute Setup

### Step 1: Run the Setup Script (1 minute)

```bash
cd "/Volumes/JEW/NFC DEMO/NFC DEMO/NFCDemo"
./setup.sh
```

The script will:
- ✅ Create `Config.plist` from template
- ✅ Verify security settings
- ✅ Check dependencies
- ✅ Validate configuration

### Step 2: Add Your Credentials (2 minutes)

1. Get your Supabase credentials:
   - Go to [https://app.supabase.com/project/_/settings/api](https://app.supabase.com/project/_/settings/api)
   - Copy your **Project URL**
   - Copy your **anon/public key**

2. Edit `NFCDemo/Config/Config.plist`:
   ```xml
   <key>SUPABASE_URL</key>
   <string>https://YOUR-PROJECT-ID.supabase.co</string>
   <key>SUPABASE_ANON_KEY</key>
   <string>YOUR-ACTUAL-KEY-HERE</string>
   ```

### Step 3: Add Files to Xcode (1 minute)

1. Open `NFCDemo.xcodeproj` in Xcode
2. Drag these folders into your project:
   - `Config/`
   - `Utils/`
   - `Network/`
   - `Repositories/`
   - New files in `Services/`

3. Ensure "Copy items if needed" is **unchecked**
4. Ensure target is **NFCDemo**

### Step 4: Build and Run (1 minute)

1. Select your target device (must be real iPhone for NFC)
2. Press **⌘R** to build and run
3. Test login with your Supabase credentials

## ✅ Verification Checklist

After setup, verify:

- [ ] App launches without crashes
- [ ] Can authenticate successfully
- [ ] Events load from database
- [ ] NFC scanning is available (real device only)
- [ ] Logs are being written (check Console.app)
- [ ] No warnings about missing configuration

## 🐛 Common Issues

### "Configuration not found"
**Fix**: Make sure `Config.plist` exists and has valid values (not placeholders)

### "Build failed"
**Fix**: Ensure all new files are added to Xcode project target

### "Cannot find AppConfiguration"
**Fix**: Add `Config/AppConfiguration.swift` to your Xcode project

### NFC not working
**Fix**:
- Use a real iPhone (NFC doesn't work in simulator)
- Check NFC entitlements are enabled
- Verify `Info.plist` has NFC usage description

## 📚 Next Steps

Once setup is complete:

1. **Read the Architecture** - See README.md for detailed architecture
2. **Review Migration Guide** - If you have existing code to update
3. **Write Tests** - See `NFCDemoTests/` for examples
4. **Deploy** - Follow deployment section in README.md

## 🆘 Need Help?

- 📖 Full documentation: `README.md`
- 🔄 Migration instructions: `MIGRATION_GUIDE.md`
- 📊 Implementation details: `IMPLEMENTATION_SUMMARY.md`
- 🐛 Open an issue on GitHub

---

**That's it!** You should now have a fully functional, secure NFC event management app. 🎉
