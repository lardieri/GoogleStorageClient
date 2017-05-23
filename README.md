# iOS client for Google Storage uploads using Service Account authentication

Many organizations use private data acquisition apps to collect information out in the field and upload it to a cloud storage account for back-end processing.

It is impractical to share the login credentials for the cloud storage account with each of your employees, so a typical client OAuth workflow (displaying a web page that prompts for username + password) is not appropriate for this kind of private app. Instead, you typically create a "service account" that can authenticate to the cloud service using a private key, which you then install on your own servers or devices, and use that private key to initiate an authentication workflow that does not require any user interaction.

However, the authentication workflow for a Google Storage service account requires a nonstandard extension to the JSON Web Tokens (JWT) claims set. Google requires that you specify a "scope" for the claim set, in order to determine whether the generated token should have read-only or read-write access. See Google's documentation at:

https://cloud.google.com/storage/docs/authentication#generating-a-private-key

There is a Cocoapod, appropriately called "JWT," that can help iOS developers form proper JSON Web Tokens. As of version 2.2.0, JWT does not support the Scope property for the claim set, but an outstanding pull request (which would create a new version 2.2.1) adds that capability.

This project uses the forked JWT (unofficial version 2.2.1) and demonstrates how you can authenticate to Google Cloud using a service account, then use the returned token to upload some data to a Google Storage bucket.


## IMPORTANT DISCLAIMER

You should never bake a private key directly into any app that you intend to distribute through the App Store. That is a severe security flaw. Any script kiddie can download your app bundle into the iTunes directory on their computer and find your key using a variety of tools ("man strings" for the most basic of these)

The technique demonstrated here is only for private apps that you only place on trusted devices and only distribute to employees of your own organization.
