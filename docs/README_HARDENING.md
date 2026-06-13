As a developer, “proper tamper protection” is layered. Code signing alone proves integrity at launch, but once code is running on a user-controlled machine, you cannot make tampering impossible. You can only raise cost, detect likely modification, and keep important authority server-side.

For macOS apps, I’d think about it like this:

**1. Sign and notarize correctly**

Use a real Developer ID certificate for distribution:

```bash
codesign --force --deep \
  --options runtime \
  --timestamp \
  --sign "Developer ID Application: Your Company (TEAMID)" \
  YourApp.app
```

Then notarize and staple the ticket. Hardened Runtime should be enabled unless you have a specific reason not to.

Avoid debug-style entitlements in release builds:

```xml
com.apple.security.get-task-allow
```

should be absent or `false`.

Also avoid unnecessary relaxations such as:

```xml
com.apple.security.cs.disable-library-validation
com.apple.security.cs.disable-executable-page-protection
com.apple.security.cs.allow-dyld-environment-variables
```

Only grant them if your app genuinely needs them.

**2. Verify your own signature at runtime**

At startup and before sensitive actions, check that the running bundle is signed by your expected Team ID and requirement.

On macOS this is typically done with Security.framework APIs such as:

```c
SecCodeCopySelf
SecCodeCopySigningInformation
SecRequirementCreateWithString
SecCodeCheckValidity
```

You can verify a requirement like:

```text
anchor apple generic and
certificate leaf[subject.OU] = "YOURTEAMID" and
identifier "com.yourcompany.yourapp"
```

This helps detect ad-hoc re-signing, altered signatures, or repackaged builds.

**3. Check nested code**

If your app ships frameworks, plugins, helpers, or dylibs, verify them too. Attackers often modify nested code instead of the main executable.

Use strict signing during build:

```bash
codesign --verify --deep --strict --verbose=4 YourApp.app
```

At runtime, avoid loading code from writable locations unless you explicitly verify it.

**4. Keep Hardened Runtime tight**

Hardened Runtime blocks several common tampering paths. Do not disable protections casually.

Prefer:

```text
Hardened Runtime on
Library validation on
No get-task-allow
No DYLD environment entitlement
No unsigned executable memory unless required
```

If you need JIT, plugins, or scripting, isolate that functionality and narrowly scope the entitlement.

**5. Move authority server-side**

Anything purely local can eventually be patched. For games or licensed software, do not trust the client for important state.

Examples:

- license ownership
- paid entitlements
- competitive scores
- multiplayer authority
- currency balances
- anti-cheat decisions
- unlock state that affects online systems

The client can present UI and cache state, but the server should validate important decisions.

**6. Add integrity checks, but do not rely on one check**

Runtime self-checks can help, but assume they can be patched out. Use multiple checks in different places:

- verify code signature
- verify key resource hashes
- verify expected bundle identifier and Team ID
- check loaded dynamic libraries
- check unexpected writable/executable mappings
- detect debugger attachment for release builds
- detect suspicious environment variables like `DYLD_INSERT_LIBRARIES`

Do this carefully. False positives are worse than weak protection if they break legitimate users.

**7. Separate secrets from the client**

Never ship long-term server secrets, private keys, signing keys, or irreversible licensing secrets in the app. Obfuscation can slow inspection, but it does not make embedded secrets safe.

Use asymmetric designs where the app can verify server-signed data with a public key, but cannot mint valid data itself.

**8. Use obfuscation only as friction**

For Swift/Objective-C/C#/Unity apps, obfuscation can slow casual tampering, especially symbol stripping and managed-code obfuscation. But it should be treated as delay, not security.

For Unity specifically, IL2CPP generally raises the bar compared to easily editable managed assemblies, but native code is still reversible.

**9. Make tamper response proportional**

Do not crash mysteriously. Prefer controlled degradation:

- disable online features
- require re-download
- refuse license validation
- mark telemetry for review
- show a clear “app integrity check failed” message where appropriate

For games, avoid heavy-handed local punishments based only on client-side detection.

**Practical release checklist**

```bash
codesign -dv --verbose=4 YourApp.app
codesign -d --entitlements :- YourApp.app
codesign --verify --deep --strict --verbose=4 YourApp.app
spctl --assess --type execute --verbose=4 YourApp.app
```

For a hardened release build, you generally want:

```text
Developer ID signature: yes
TeamIdentifier: expected value
Hardened Runtime: yes
Notarized: yes
get-task-allow: absent
dangerous cs.* entitlements: absent unless justified
```

The strongest design is: signed and notarized app, minimal entitlements, runtime signature checks, server-side authority for valuable state, and no secrets embedded in the client.
