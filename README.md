# AgentGrid Cloud Desktop GUI (Linux in Browser)

Run and test [AgentGrid (agentgrid.sh)](https://agentgrid.sh) — the desktop application with an **infinite canvas** for managing and orchestrating multi-agent AI coding workflows — entirely inside your browser via **GitHub Codespaces** or Docker, without installing anything locally.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/abhishek20nn/linux-gui)

---

## 📋 What is AgentGrid?

**AgentGrid** (`agentgrid.sh`) is a visual workspace designed for developers and AI engineers. Instead of a single chat thread, it provides an infinite canvas where you can arrange:
- **Coding Agents**: Claude Code, Codex, Cursor, OpenCode, and custom harnesses.
- **Terminal Windows & Dev Servers**: Run backend and frontend commands right next to the agent modifying the code.
- **Browser Previews & Diffs**: View real-time web previews and git diffs directly beside your agents.
- **Coordinator & Multi-Agent Teams**: Delegate tasks across Builder, QA, and Manager roles with shared context.

Because AgentGrid is natively a desktop GUI application (Electron), running it in the cloud requires an X11 virtual desktop environment with **noVNC** (web-based VNC client). This repository provides that ready-to-use configuration.

---

## 🚀 Quickstart: Run in GitHub Codespaces (1-Click)

### Step 1: Launch the Codespace
Click the badge above or navigate to [https://codespaces.new/abhishek20nn/linux-gui](https://codespaces.new/abhishek20nn/linux-gui) and click **Create codespace**.

### Step 2: Automatic Initialization
GitHub Codespaces will automatically:
1. Spin up the DevContainer with `desktop-lite` (Fluxbox X11 desktop + noVNC).
2. Run `.devcontainer/install-agentgrid.sh` to download and install the latest Linux release of AgentGrid (`.deb` package) and all required GUI/Electron libraries.
3. Configure the launcher with `--no-sandbox` (essential for Electron inside Docker).

### Step 3: Open the Web Desktop
1. In the bottom panel of VS Code / Codespaces, click the **Ports** tab.
2. Find Port **`6080`** (labeled **AgentGrid Web Desktop (noVNC)**).
3. Click the **Open in Browser** (globe) icon or follow the auto-opened browser tab.
4. You will see the Linux desktop GUI running in your browser tab!

### Step 4: Launch AgentGrid
To launch AgentGrid:
- In the Codespaces terminal, run:
  ```bash
  ./launch-agentgrid.sh
  ```
- Or switch to your browser desktop tab and double-click the **AgentGrid** desktop shortcut or right-click anywhere on the desktop -> **Applications** -> **AgentGrid**.

AgentGrid will launch on the virtual desktop canvas!

---

## 🛠️ Repository Structure

```
├── .devcontainer/
│   ├── devcontainer.json        # Codespaces devcontainer with desktop-lite feature
│   ├── install-agentgrid.sh     # Automated dependency & AgentGrid .deb installer
│   └── post-start.sh            # Post-start helper & notification banner
├── launch-agentgrid.sh          # Quick launcher script (sets DISPLAY and --no-sandbox)
├── install.sh                   # Manual installer entrypoint
├── Dockerfile                   # Standalone container for local/VM/HuggingFace testing
├── docker-compose.yml           # 1-command Docker Compose setup
├── supervisord.conf             # Process supervisor for headless X11 + noVNC
└── README.md                    # Documentation & setup guide
```

---

## 🐳 Alternative: Run Locally or on a Cloud VM with Docker

If you prefer to run it on your local computer via Docker Desktop or on a cloud virtual machine (AWS EC2, Google Cloud Compute, DigitalOcean, Hetzner, etc.):

```bash
# Clone the repository
git clone https://github.com/abhishek20nn/linux-gui.git
cd linux-gui

# Build and start container
docker-compose up --build
```

Then open your browser and navigate to:
```
http://localhost:6080/vnc.html
```

---

## ⚙️ AI Agent Setup inside AgentGrid

Once AgentGrid is open on your desktop canvas:

1. **Open Settings**: Click the settings icon in the sidebar or press `Ctrl + ,`.
2. **Configure Harnesses**:
   - **Claude Code**: Run `npm install -g @anthropic-ai/claude-code` in the terminal and authenticate with `claude`.
   - **Codex / OpenCode**: Enter your API key or configure your local CLI provider.
3. **Infinite Canvas**:
   - Drag terminals, agents, and note cards.
   - Assign roles (e.g. Coordinator, Builder, QA Reviewer) and orchestrate your coding tasks visually.

---

## 🔍 Troubleshooting & Pro Tips

| Issue | Solution |
| :--- | :--- |
| **Electron "No usable sandbox" error** | Inside Docker containers, Chromium requires unprivileged sandbox flags. The included `launch-agentgrid.sh` automatically passes `--no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage`. |
| **Blank or black screen on Port 6080** | Wait 5–10 seconds for the Fluxbox window manager to initialize, or refresh the browser tab. |
| **Screen Resolution Scaling** | Click the noVNC sidebar tab on the left edge of the browser window, click the Settings (gear) icon, and choose **Scaling Mode: Remote Resizing** or **Local Scaling**. |
| **Manual Re-installation** | If you need to reinstall AgentGrid at any time, run: `bash .devcontainer/install-agentgrid.sh` |

---

## 📄 License
MIT License. AgentGrid is property of [agentgrid.sh](https://agentgrid.sh).
