# Word Reader

An iPhone speed reader for EPUB books, based on the included WPF prototype. The reader shows one word at a time with its focal character aligned to the center.

## Run on an iPhone

1. Open `WordReader2.xcodeproj` in Xcode and allow it to resolve its Swift packages.
2. Select the WordReader2 target, choose your Apple development team under **Signing & Capabilities**, and change the bundle identifier if necessary.
3. Connect your iPhone, select it as the run destination, and run the app. The minimum supported version is iOS 16.0.
4. Tap **Open an EPUB to begin** or **Read** to select an EPUB. You can also choose **Open EPUB from Files** in the reading menu, where you can set the reading speed and open **Select chapter** to choose a chapter.

Tap **Read** to start or **Pause** to stop. The reader advances through chapters automatically, shows overall progress and the estimated time remaining in the current chapter, and pauses when the app leaves the foreground. After finishing, **Read again** starts at the beginning. The reading speed is shared across books and remembered between launches.

Choose **Dark**, **White**, or **Device** under Appearance in the reading menu. Device follows the iPhone's light or dark appearance. The selected theme is remembered between launches.

Imported books appear under **Recent books** in the reading menu. The app keeps a private copy of each EPUB and saves its reading position independently; the most recently opened book is restored on launch. Progress is saved when pausing, switching chapters or books, leaving the app, and approximately once a second during playback. Reimporting the same file resumes its saved position.

The app reads unprotected EPUBs with HTML or XHTML content in their reading order. DRM-protected books and other reading-order content formats are not supported. Saved books use device storage and are removed if the app is deleted.

## Tests

Run the WordReader2 scheme's tests in Xcode, or use `xcodebuild test -project WordReader2.xcodeproj -scheme WordReader2 -destination 'platform=iOS Simulator,name=iPhone 14'` with an available simulator.
