# Word Reader

An iPhone speed reader for EPUB books. The reader shows one word at a time with its focal character aligned to the center.

The interface follows the device language and supports English and Brazilian Portuguese. Other languages fall back to English; book text and titles remain in their original language.

## Run on an iPhone

1. Open `WordReader2.xcodeproj` in Xcode and allow it to resolve its Swift packages.
2. Select the WordReader2 target, choose your Apple development team under **Signing & Capabilities**, and change the bundle identifier if necessary.
3. Connect your iPhone, select it as the run destination, and run the app. The minimum supported version is iOS 16.0.
4. Tap **Open an EPUB to begin** or **Read** to select an EPUB. You can also choose **Open EPUB from Files** in the reading menu, where you can set the reading speed and open **Select chapter** to choose a chapter.

Tap **Read** to start or **Pause** to stop. The reader advances through chapters automatically, shows overall progress and the estimated time remaining, and pauses when the app leaves the foreground. Open **Remaining time** in the configuration menu to choose **Chapter** (the default) or **Book**. After finishing, **Read again** starts at the beginning. The reading speed and remaining-time selection are shared across books and remembered between launches.

Open **Theme** under Appearance in the reading menu to choose **Dark**, **White**, or **Device**. Device follows the iPhone's light or dark appearance. The selected theme is remembered between launches.

Choose an **Accent color** under Appearance. Red is the default, and the selected color is remembered between launches.

Enable **Zen mode** under Appearance to hide the book and chapter titles and the reading button. Tap the word or the surrounding screen to start, pause, or restart reading; the configuration menu remains available. With no book loaded, tap to open the EPUB picker. The setting is remembered between launches.

Open **Reading style** to choose **Flash** for the original one-word display or **Flow** to see the previous and next words alongside the current word, without animation. The reading style is remembered between launches.
In Flow, neighboring words are cropped at the edges when necessary; the font shrinks only when the current word cannot fit.

Imported books appear under **Recent books** in the reading menu. The app keeps a private copy of each EPUB and saves its reading position independently; the most recently opened book is restored on launch. Progress is saved when pausing, switching chapters or books, leaving the app, and approximately once a second during playback. Reimporting the same file resumes its saved position.

The app reads unprotected EPUBs with HTML or XHTML content in their reading order. DRM-protected books and other reading-order content formats are not supported. Saved books use device storage and are removed if the app is deleted.

## Tests

Run the WordReader2 scheme's tests in Xcode, or use `xcodebuild test -project WordReader2.xcodeproj -scheme WordReader2 -destination 'platform=iOS Simulator,name=iPhone 14'` with an available simulator.
