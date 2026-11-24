## ZLT X28 1.4.0

**Split tunnelling and a kill switch, and the engines underneath are current.**

**Split tunnelling** — Iranian destinations now leave through the carrier instead of the tunnel, the way Amnezia's own exclude list works. A list of 1,747 Iranian networks ships with the app; every device on the Wi-Fi gets the bypass, so Digikala, Snapp, Divar and bank sites stop taking the long way around. Implemented on the router with an ipset, a firewall mark on LAN traffic and one policy rule ahead of the tunnel's table. The list is refreshed whenever setup runs.

**Kill switch** — with it on, if the tunnel drops the internet stops instead of quietly falling back to the carrier. Iranian/bypass traffic keeps working, because the block only applies to traffic that was supposed to be tunnelled. The watchdog enforces it every 20 seconds, so it survives a daemon restart, and turning the VPN off deliberately never leaves the house offline.

Both have a switch on the VPN page in the Mac app and on the router's phone page.

**Engines updated:**
- The AmneziaWG engine was rebuilt from current source with 3.1 support (this is what made your Rabisu config work in 1.3.2).
- sing-box went from 1.14.3 to **1.14.4**, the current release, installed on the router and shipped in the app.
- The Iranian range list is new and installed with setup.

Verified on the router: 1,747 prefixes loaded, the mark rule and policy rule present, a marked lookup following the carrier while unmarked traffic follows the tunnel; the kill switch's block rule appearing when the tunnel is down and disappearing when it returns; and both toggles changing the live router from the app and the phone page.

One honest limit: the bypass is by **IP range**, not by domain name. Iranian sites hosted on Iranian networks bypass correctly; an Iranian site served from a foreign CDN will still go through the tunnel. The router's resolver is built without ipset support, so domain-based classification would mean replacing it — a separate job.

## ZLT X28 1.3.2

**The tunnel works again, and Amnezia links and draggable files are in.**

The reason nothing would connect was a version gap, not a dead server. The new Amnezia servers speak **AmneziaWG 3.1**, whose handshakes carry a `HeaderProtectionKey`. The engine installed on the router was older and refused that field outright (`errno=-22`), so the config could never even be loaded — the app reported "no handshake" because that was the last thing it could see. I rebuilt the engine from current source with 3.1 support, installed it on the router, and switched to the config carried inside your new Rabisu `vpn://` link. It now handshakes, passes traffic, and the LAN exits through `45.155.125.63`. The new engine ships inside the app, so a fresh Router setup installs it too.

Two of the three interface requests are in:

- **Paste an Amnezia `vpn://` link** into the link box and it becomes a config. The link is decoded on this Mac (base64 → zlib → JSON), the client config inside it is extracted, its range values (`25-35`) and on/off words are turned into numbers the engine accepts, and it is imported like any other file. Nothing is sent anywhere to do this.
- **Drag `.conf` files onto the VPN page** — one or many — and each is copied to the router. The page shows a drop target while you drag.

Not yet: ⌘-click / ⇧-click multi-select with a Delete key. That needs the config and link lists rebuilt around a selection model, and I would rather do it deliberately than ship a half-working list at the end of a long night.

## ZLT X28 1.3.1

**No more endless spinner.** Turning the tunnel on ran an SSH command with a two-minute limit, and then a full re-read of the router with no limit at all — so whenever the router was slow, wedged, or off the network, the app looked frozen and the only way out was to quit it. Fixed in four places:

- The app checks the router with a 3-second connection test before it reads anything. If the router is not there, it says so and reads nothing else.
- Every button that talks to the router refuses to run when the router is unreachable, and says why, instead of starting a command that cannot finish.
- Turning the tunnel on or off is now limited to 60 seconds. If the router never answers, the spinner ends and you get a sentence saying the router stopped answering.
- Starting the sing-box engine is limited to 90 seconds, for the same reason.

The router-side script was hardened too, because a wedged `procd` lock could make the start block forever. Its calls to the service manager and its config push now time out, and it prints what it is doing ("pushing the config to the engine…", "config applied — waiting for the server to answer…") so a failure is legible. The "no handshake" message now says what it means: the server did not answer, the config may be stale (the server no longer knows that key), or the server is blocked from this line.

**The current tunnel failure is real, and separate.** With the Racknerd config on the router, the server never answers the handshake; with the old Rabisu config it answers but carries no traffic. The engine itself is fine — it accepts both configs. The fix is to import the config that actually works on the Mac (AmneziaVPN → export/share that server's config) and use it here.

## ZLT X28 1.3.0

**The router now has its own web page.** Open `http://192.168.70.1/zlt.html` on any phone, tablet or TV browser on the Wi-Fi and you get the same controls as the Mac app's VPN screen: whether the VPN is on, one big switch, the configs and links on the router, and Use/Delete for each. Nothing to install on the phone, and it keeps working when the Mac is asleep or off.

It is served by the router itself — a small page in the router's web folder plus a tiny script that calls the same `/usr/bin/vpn` the app calls. Setup installs it along with the engine.

**And it repairs itself.** A firmware update can wipe the router's web folder. The app checks for the page every time it reads the router; if it is missing, it copies it back without being asked and says so. There is also an **Open web app** card on Home with the address, a copy button, and a **Put it back** button.

Two things to know. It asks for no password, because it sits on the same LAN as the stock admin page and does only what the Mac app does — so anyone on your Wi-Fi could use it. And it can do VPN things only: no SIM, APN, Wi-Fi or firmware changes.

Verified end to end: the page loads over the router, the API answers with the live config list, the switch and delete calls work, and deleting both files and relaunching the app put them back with the right permissions.

## ZLT X28 1.2.1

**The trash button deletes.** It used to rename a config to `.disabled-<time>` on the router and move a link into a `trash` folder — "setting it aside" — which meant a delete you asked for left a file behind, and in the configs list the renamed file even came back as a new entry called `rabisu.disabled-1795446485`. That was not what a trash button means.

Now it removes the file outright: the config, any older `.disabled-` copy of it, the link's generated files, and any copy already sitting in the router's trash folder. If the thing you delete is the one carrying traffic, the app stops the tunnel first and says so. Nothing is kept "in case". The one place this matters: the app can no longer bring a deleted config back, so keep your own copy of anything you might want again. The **What it does** page says exactly that.

Two smaller things came with it. The configs list no longer shows those `.disabled-` leftovers as if they were configs — they were only ever remnants of the old behaviour. And the config engine's copy now says what it has always accepted: plain **WireGuard** as well as AmneziaWG. Windscribe, Mullvad, Proton and IVPN all hand out WireGuard `.conf` files, and they import here the same way an AmneziaWG one does.

Verified on the router: deleting a config removed both the file and its `.disabled-` copy; deleting a link removed its `.json`, `.test.json`, `.link` and its trash folder; and a plain WireGuard config (no obfuscation fields) was accepted and pushed by the engine.

## ZLT X28 1.2.0

**Every screen now says what it will do to your router before it does it, and one new page says it all in one place.**

The app has always been careful with the router — it installs an engine, sets a band preference, starts and stops a tunnel — but it kept that care to itself. You had to read the README to learn that setup never flashes firmware, that Health never writes anything, that removing a link moves it aside instead of deleting it. A person should not have to find out what a button does by pressing it.

So there is a new page in the sidebar, **What it does**, with five lists: what the app does, what it never touches (the SIM and the plan, the APN, the Wi-Fi name and password, the router's password, the firmware, this Mac's own internet), what it needs, what it cannot do, and what it writes and where. The "cannot" list is the one worth reading. It cannot create signal, make a slow line fast, lift a carrier's wall, or run both engines at once.

The other pages carry the same thing in one line at the top, limited to their own job. Health's line says it only looks. Setup's says it adds three things and nothing else. The SIM page's says the only change Optimize can make is a band preference, and that it puts that back when the test does not help.

The two buttons that interrupt the tunnel — Restart on VPN, Restart tunnel on Health — now ask first, and the question says what will happen: every device on the Wi-Fi drops for a few seconds, and nothing on the router changes.

Two smaller fixes came from watching the app launch. The Router line used to read "Not reachable" for the second or two before the router answered, when the truth was "I have not asked yet". It now says **Checking…** until there is an answer. And Health printed its six readings even when the router could not be seen at all, which meant six confident claims — not installed, traffic goes direct, will not start by itself — about a machine the app had never reached. That card now says nothing has been read and why, and the readings appear when there is something behind them.

One correction to the 1.0.0 notes, which said the app does not import OpenVPN **or WireGuard** files. That was wrong about WireGuard. A `.conf` file is the main way into this app and has been since the first build; what the app refuses is OpenVPN. The new page states it correctly.

Nothing about the router changes in this version. It is a change to what the app tells you about itself.

## ZLT X28 1.1.1

**The app now knows which build it is, and the update check follows the code, not the release page.** Two small things, both about the app being honest about itself.

The About card used to print "1.0" no matter which version you were running — a hardcoded string left from the first build. It now reads the version out of the app itself, so an update that lands is the version you see.

The update check used to ask GitHub for the newest *release*. That sounds right until you push a fix and do not cut a release: the app tells you it is current while newer code sits on the branch. Every build now stamps the commit it was compiled from into its own Info.plist, and the check compares that against `main`. If a release is newer than your version, it offers the release. If only the branch has moved, it says so and gives you the date of the newest commit.

Nothing about the router changes in this version. It is a fix to the app only.

## ZLT X28 1.1.0

**The checks now start with the line, not the tunnel.** A carrier can give you an address, a route and a signal, and still let you reach nothing but its own website. Every other check in this app passes in that state, because the router, the engine and the tunnel are all fine. What fails is the thing the tunnel was supposed to carry.

So Health now tests the SIM's own connection first, without the VPN: it reaches an Iranian site directly on the router's default interface, then reaches the carrier's own site. Three outcomes, and the app names which one you are in.

- The open internet answers: the line is fine and any problem after this point is the tunnel's.
- Only the carrier answers: the line has a captive session. This is not the router and not the VPN, and switching the tunnel on will not change it. It usually means the line has no data package for use in a modem, which carriers sell separately from phone packages, or that its identity check (احراز هویت) is unfinished.
- Nothing answers: the SIM is not seated, or data is off.

I added this after a weekend on a router that looked perfect from every angle and had no internet, because the SIM's line was serving a walled garden. Nothing in the app could see it. Now it can.

## ZLT X28 1.0.0

This app is for the ZLT X28, the 5G router I use for my own connection.

I made it after a lot of digging. Getting a VPN to run on this router at all was a wild goose chase, and getting the right numbers for Iranian carriers like MCI and IranCell took a lot of trial and error. Most of what we tried did not work. All of it was done with an AI. I did not want anyone else to go on the same search, so I got the robot to build this: what we found is already in it, and it measures your own connection instead of repeating mine.

### What it does

**The VPN runs on the router.** Turn it on and every device on the Wi-Fi goes through it; there is nothing to install on the phone or the laptop. The engine is AmneziaWG, built for this box, because the stock firmware has no WireGuard in it.

**Setup does not require flashing.** The router's DMZ field runs a command if it is set up the right way, which other people found before me. The app uses it to install an SSH key, copy the VPN engine over and start it. The firmware stays stock.

**It accepts share links.** vless, vmess, trojan, shadowsocks and hysteria2. Paste them in and the app tests each one on the router with a real download, so you can see which are dead, which work and how fast they are. Keep the one you want and remove the rest. Results are saved, so a dead link stays marked dead until you test it again.

**It shows you the radio and tests it.** Scan for the cells the router can hear and see which bands they use, or lock a band yourself. Optimize runs the A/B test: it measures the band the router picked against the band your carrier uses for speed, keeps the faster one, and puts everything back if it cannot show an improvement.

**The carrier information is built in.** IranCell and MCI differ in ways that matter on this router. What the SIM page shows is what we measured on both, not general advice.

### Installing

Unzip, move the app to Applications, and right-click it and choose Open the first time. macOS warns because the app has no paid Apple certificate. It needs macOS 13 or later.

Connect the Mac to the router with an Ethernet cable first. The router's USB-C port only provides power. Then open Router setup and follow the steps. The router should be at 192.168.70.1 with the factory password; if you changed it, the app stops and says so.

### What it does not do

Only firmware 1.5.13 is tested, because that is the version on my router. Another version may behave differently, and the app will tell you when it does not recognise yours.

It cannot create 5G where there is no 5G signal, and changing bands will not make a slow connection fast. If a link tests as dead, the carrier may be the reason.

It does not import OpenVPN or WireGuard files. Neither runs well on this router.

Made by Morad
