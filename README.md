# AppifyWeb iOS Setup Guide

## Overview
This directory contains the Swift source code for the AppifyWeb iOS application. It is designed to work with the **AppifyWeb** SaaS platform, mirroring the Android "Dynamic Shell" architecture.

## How to use
1.  **Create a New Xcode Project**:
    -   Open Xcode -> New Project -> App.
    -   Product Name: `AppifyWebiOS` (or your app name).
    -   Interface: **SwiftUI**.
    -   Language: **Swift**.

2.  **Import Files**:
    -   Drag and drop the following folders into your Xcode project navigator (ensure "Copy items if needed" is checked):
        -   `Config`
        -   `Networking`
        -   `Views`

3.  **Replace Entry Point**:
    -   Replace the default `AppifyWebiOSApp.swift` in Xcode with the `AppifyWebiOSApp.swift` provided here.

4.  **Configuration**:
    -   Open `Networking/ApiService.swift`.
    -   Update `baseUrl` to your backend URL (e.g., `https://your-domain.com/api/v1`).
    -   Update `appToken` or implement a logic to fetch it (e.g., via a unified config file or build settings).

## Features Implemented
-   ✅ **Dynamic Configuration**: Fetches app settings (colors, URLs, features) from the backend.
-   ✅ **WebView Shell**: Full-screen WebView with Pull-to-Refresh.
-   ✅ **Dynamic Navigation**: Bottom tab bar that appears/disappears based on API config and hidden paths.
-   ✅ **Subscription Check**: Auto-locks app if subscription is expired.

## Next Steps
-   **Push Notifications**: Add `UIApplicationDelegate` to handle APNs token registration.
-   **Biometrics**: Implement `LocalAuthentication` if enabled in config.
