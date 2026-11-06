# কোথায় কী পাঠাবেন

সব লেখা তৈরি আছে। আপনাকে শুধু কপি-পেস্ট আর attach করতে হবে।

---

## ধাপ ১ — ফর্মাল কেস (এটাই আসল রেকর্ড)

**https://www.dell.com/support/home** → Service Tag `CYFY434` → **Contact Support**

| ঘরটি | কী দেবেন |
|---|---|
| Issue type | **Display / Graphics** |
| Description | `COMPLAINT.md`-এর Subject আর Body, হুবহু |
| Attach | `TECHNICAL-NOTES.md` + `evidence` ফোল্ডারের ৫টা ফাইল |

**কেস নম্বর চাইবেন** — লিখে রাখুন, পরে সব জায়গায় ওটাই ব্যবহার করবেন।

---

## ধাপ ২ — Dell Community (এইটাই সবচেয়ে কাজে দেয়)

**https://www.dell.com/community/** → **Laptop** → **G Series**

**Title:** `COMPLAINT.md`-এর Subject লাইনটা

**Body:** একই Body, শেষে এই দুটো লাইন যোগ করবেন:

```
If anyone else with a G15 5530 or G16 7630 can check, two simple numbers say whether
they have it: Get-PnpDevice -Class Monitor | Where-Object Status -eq 'OK'  and the CPU
time of dwm.exe. On my machine those read 2 devices and 31-54% while the panel is on
the NVIDIA GPU.
```

**Attach:** শুধু `measurements.csv` (কমিউনিটি বড় ফাইল নেয় না)

**কেন এটা জরুরি:** Dell-এর ইঞ্জিনিয়ারিং টিম কমিউনিটি পড়ে। আর অন্য মালিকরা একই সমস্যা পেলে "me too" লিখবে — তখন এটা একক অভিযোগ থেকে **প্ল্যাটফর্ম ইস্যু** হয়ে যায়। সেটাই কেস ক্লোজ হওয়া থেকে বাঁচায়।

---

## ধাপ ৩ — সোশ্যাল (দ্রুত সাড়ার জন্য)

**X-এ `@DellCares`**-কে মেনশন করে:

```
G15 5530, BIOS 1.36.0, Dell driver A17 + NVPCF 615.34. Using Advanced Optimus leaves
2 monitor devices for 1 panel; dwm.exe holds 31-54% of a core and input stalls for about
a second. Clearing it kills brightness control. Case: <কেস নম্বর>. Is this known?
```

**Dell Bangladesh:** https://www.dell.com/bd — এখানে লোকাল সাপোর্ট পার্টনারের নম্বর আছে। ফোনে একই কথা, কেস নম্বর দিয়ে।

---

## ধাপ ৪ — এস্কালেশন

| দিন | কী করবেন |
|---|---|
| **০** | কেস + কমিউনিটি + X |
| **৩** | কেসে ফোনে ফলো-আপ, লিখিত আপডেট চান |
| **৭** | কেসে লিখুন: *"Requesting escalation to platform engineering. This reproduces on Dell's own validated driver package and the newest BIOS."* |
| **১৪** | @DellCares-এ আবার, কেস নম্বর দিয়ে, পাবলিকভাবে |

---

## ফোনে ওরা যা বলবে — আর আপনার উত্তর

| ওরা বলবে | আপনি বলবেন |
|---|---|
| "ড্রাইভার রিইনস্টল করুন" | "Already done — Dell package A17 with NVPCF 615.34, generic driver removed. It still happens. Section 6 of the attached notes." |
| "BIOS আপডেট করুন" | "BIOS is 1.36.0, the newest listed for this service tag." |
| "এটা তো গেমের সমস্যা" | "It happens idle on the desktop with nothing running. dwm.exe sits at 31–54% with no application open." |
| "আপনার সেটিংসের সমস্যা" | "Clean install of the whole graphics stack, then reboot, then measured again. Same result." |
| "আমরা রিপ্রোডিউস করতে পারছি না" | "Two commands reproduce it. I can run any diagnostic you want on the machine." |

**ওদের ড্রাইভার রিইনস্টল করতে দেবেন না।** ওটা ওদের প্রথম প্রস্তাব, আর আপনার নোটে আগেই উত্তর দেওয়া আছে।

---

## যেসব কথা তুলবেন না

- AWCC, tcc-g15, রেজিস্ট্রি এডিট, DPI — এগুলোর সাথে বিষয়টার সম্পর্ক নেই, শুধু কেস ঘোলা করবে
- "আমি অনেক টাকা দিয়েছি" — সাপোর্ট কিউতে এটা কাজ করে না
- আমার বানানো টুলের কথা — Dell-এর কাছে ওটা অপ্রাসঙ্গিক

---

## বাস্তবতা

| ফল | সম্ভাবনা |
|---|---|
| ড্রাইভার রিইনস্টল বলে কেস বন্ধ | বেশি — কিন্তু আপনার নোটে উত্তর আগেই আছে |
| L2 / প্ল্যাটফর্ম ইঞ্জিনিয়ারিং-এ এস্কেলেট | মাঝারি — কমিউনিটিতে অন্যরা যোগ দিলে অনেক বাড়ে |
| পরের BIOS/NVPCF-এ ফিক্স | কম, তবে অসম্ভব নয় |

**তাই:** রিপোর্ট পাঠান, কেস নম্বর রাখুন, আর মেশিনে Optimus-এ থাকুন। ওদিকে কিছু হলে জানবেন।
