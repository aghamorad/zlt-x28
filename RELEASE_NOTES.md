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
