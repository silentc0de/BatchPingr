# ⚡ BatchPingr — Compiled Version 3 (✨ Final Release)

**BatchPingr** is a fast, lightweight URL and .onion link validation tool that sends **mass HTTP HEAD** requests to check which links are alive — perfect for uptime or mirror checks 🌍  Works on Android
Built in collaboration with **ChatGPT 4_turbo 🤖**

---

### ⚙️ Quick Setup

```bash
pkg install python
pip install requests
termux-setup-storage
python batchpingr.py
```
---

## 🚀 Features & Highlights

**🧠 Smart File Detection**  
→ Automatically finds `links.txt` or `links.docx`.  
→ If none exist, it creates a sample file automatically ✅  

**🧩 DOCX Auto‑Parsing**  
→ Extracts links from `.docx` using built‑in zip + regex magic — no external dependencies ⚙️  

**⚙️ Batch HEAD Requests**  
→ Sends fast HTTP HEAD requests (no page downloads).  
→ Super efficient for large batches or continuous monitoring 🚀  

**🌐 Dynamic Tor Detection**  
→ Detects a local Tor proxy (`127.0.0.1:9050`) 🧅  
→ Tests `.onion` links only if Tor is running 🌌  
→ Skips safely if not connected ⚡  

**🗂️ Auto‑Saving Results**  
→ Saves verified links into `uplinks.txt`.  
→ Multi runs sequentially names new files (`uplinks2.txt`, `uplinks3.txt`, etc.) to preserve history 📁  

**📊 Console Summary**  
Displays a quick summary after every scan:
```
Total X | bad Y | skipped Z ✅
```

---

### 🧅 Optional Tor Integration

```bash
pkg install tor
tor &
```
Enable Tor and rerun **BatchPingr** for `.onion` checks 🌐

---

### 💡 At a Glance

| 🔹 | Description |
|:--:|:-------------|
| 🚀 | Sends mass HTTP HEAD requests |
| 🤖 | Uses only built‑in modules + `requests` |
| 🧾 | Reads `.txt` or auto‑converts `.docx` |
| 🔒 | Skips `.onion` if Tor inactive |
| 💾 | Saves clean outputs to auto‑named files |
| 🪶 | Lightweight, fast, portable |
| 🛠️ | Designed with help from **ChatGPT 4_turbo 🤖** |

---

### 🪄 Pro Tips
- Add your own URLs to `links.txt` 🔗  
- Enable Tor for onion checks 🧅  
- Great for uptime stats, content mirror validation, and bulk URL testing ✅  

---

**Project:** 🧑‍💻 BatchPingr
**Version:** Compiled 3 ( Final Release )  
**Powered By:** *silentc0de + ChatGPT 4_turbo 🤖*  
**License:** GPL v3 👅 

