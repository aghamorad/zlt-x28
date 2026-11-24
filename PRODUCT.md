# ZLT X28 — product truth

**What it is.** A Mac remote control for a ZLT X28 5G router, plus a page the router
serves for phones. It manages one thing well: whether the house's traffic leaves through
a VPN, and through which server.

**Who uses it.** One person at home in Iran, usually at night, often in a hurry. Not a
network engineer. They may be checking whether the connection will hold for a call, or
switching servers because a site stopped opening.

**What it must do, in order.** Say whether the tunnel is up and where it exits. Turn it
on and off. Add, choose, rename and delete configs. Keep the house reachable when the
tunnel fails. Never claim something it has not measured.

**What it must never do.** Touch the SIM plan, the APN, the Wi-Fi name or password, or
the firmware. Show a spinner without an end. Pretend a dead server is alive.

**Surfaces.** macOS app (SwiftUI), router-hosted phone page, Android helper app, and the
router's shell scripts.
