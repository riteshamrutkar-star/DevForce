<div align="center">
  <img src="https://img.shields.io/badge/GDG-Hackathon_Submission-blue?style=for-the-badge&logo=google" alt="GDG Hackathon" />
  <br><br>

  <h1><img src="assets/logo.png" width="40" style="vertical-align: middle; margin-right: 10px;" /> DevForce</h1>
  <p><b>Stop scrolling. Start building.</b></p>
  
  > *"Because finding a good co-founder shouldn't be harder than centering a div."*
  
  <p>
    <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
    <img src="https://img.shields.io/badge/Firebase-FFCA28?style=flat-square&logo=firebase&logoColor=black" />
    <img src="https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white" />
    <img src="https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white" />
  </p>
</div>

---

## 💡 The Vision
LinkedIn is too formal. Twitter is too noisy. Meetups only happen once a month. 

**DevForce** is "Tinder for Developers", a location-based matchmaking platform designed to connect you with local tech talent, whether you need a mentor, a UI designer, or a pair-programming buddy. Swipe, match, and collaborate in real-time.

---

## 🛠️ The Hack: What's under the hood?

I wanted this to feel like a premium startup product, not just a weekend hack. Here is what I engineered:

### 🗺️ Zero-Cost Proximity Mapping
Instead of surrendering to paid Google Maps API keys, I built a custom map engine using **OpenStreetMap** (`flutter_map`). It calculates live distances between developers and plots them on a canvas. 
* **The Challenge:** Handling GPS timeouts and coordinate math bugs (NaN crashes) during pinch-to-zoom gestures.
* **The Hack:** Implemented strict camera boundary constraints and fallback location resolvers.

### 💬 WhatsApp-style Live Chat
Matching is useless without communication. I built a real-time messaging system that runs on Firestore streams.
* **The Hack:** Instead of heavy database reads, the bottom navigation bar actively listens to a lightweight stream to render unread message badges and `lastSenderId` logic instantly.

### 🎨 Hand-Crafted Glassmorphism
No generic Material templates were used. The UI features custom `GlassCard` widgets, backdrop blurs, and an **Animated Mesh Background** that breathes life into the app without tanking the frame rate.

---

## 🚀 For the Judges: Frictionless Testing

I know you have 50+ projects to review. I made testing this one effortless.

```bash
# 1. Clone the repo
git clone https://github.com/riteshamrutkar/DevForce.git

# 2. Jump in
cd DevForce
flutter pub get

# 3. Hit run
flutter run
```

### 🔓 The "Hackathon Security Bypass"
Usually, committing `google-services.json` is a huge Git taboo. **I explicitly left it in the repository for you.** You do not need to create a Firebase project, configure SHA-1 keys, or set up databases. It works entirely out of the box. 

*Tip: Log in with two different Google accounts on two emulators to see the real-time chat badges and live map updates work instantly!*

---
<div align="center">
  Built with blood, sweat, and lots of coffee by <b>VectorFlow</b> for GDG.
</div>
