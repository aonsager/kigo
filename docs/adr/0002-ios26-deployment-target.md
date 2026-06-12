# Deployment target is iOS 26, matching the only testable runtime

The app's minimum deployment target is iOS 26, and all evidence runs on an iOS 26
iPhone 17 simulator. A reader might expect a lower floor for wider device reach.

We chose iOS 26 because it is the only simulator runtime installed on the build
machine (26.2 / 26.4 under Xcode 26.4.1), so it is the only OS on which the
autonomous loop can actually verify the app builds and runs. Claiming a lower floor
(e.g. iOS 17/18) would assert support we cannot test, and would force `#available`
gating that no real old-OS device here could exercise — exactly the kind of
unverifiable proxy signal this project avoids. Aligning the floor with the test
runtime keeps every "builds and runs" claim honest and removes availability
branching. Lowering the target later is cheap and reversible once older runtimes
are installed; it is deliberately not promised now.
