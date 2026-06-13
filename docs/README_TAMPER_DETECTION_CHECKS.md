Assuming you mean **tamper detection**: you usually cannot prove absence, but you can find indicators.

For a macOS app, check these layers.

**1. Code-signing posture**

```bash
codesign -dv --verbose=4 SomeApp.app 2>&1
codesign -d --entitlements :- SomeApp.app 2>&1
spctl --assess --type execute --verbose=4 SomeApp.app
```

Interesting signs:

```text
flags=0x10000(runtime)
TeamIdentifier=...
Authority=Developer ID Application...
```

Hardened Runtime, a real Team ID, and notarization do not prove tamper detection, but they show the app is using Apple’s integrity model.

**2. Suspicious Security.framework imports**

Look for APIs used to verify signatures at runtime:

```bash
nm -m SomeApp.app/Contents/MacOS/* | grep -E 'SecCode|SecStaticCode|SecRequirement|SecTask'
```

Notable APIs:

```text
SecCodeCopySelf
SecCodeCheckValidity
SecStaticCodeCreateWithPath
SecCodeCopySigningInformation
SecRequirementCreateWithString
SecTaskCopyValueForEntitlement
```

These often indicate runtime signature, Team ID, entitlement, or bundle verification.

**3. Anti-debug indicators**

```bash
strings SomeApp.app/Contents/MacOS/* | grep -Ei 'ptrace|sysctl|debugger|get-task|task_for_pid|amfi|csops'
nm -m SomeApp.app/Contents/MacOS/* | grep -Ei 'ptrace|sysctl|task_for_pid|csops'
```

Common anti-debug/tamper-related calls include:

```text
ptrace
sysctl
csops
task_for_pid
isatty
getppid
```

Presence is not proof. Many legitimate apps use some of these for normal diagnostics.

**4. Resource/hash checks**

Search for strings suggesting integrity validation:

```bash
strings SomeApp.app/Contents/MacOS/* | grep -Ei 'hash|sha256|signature|integrity|tamper|checksum|crc|manifest'
```

Also inspect bundled files:

```bash
find SomeApp.app -iname '*manifest*' -o -iname '*hash*' -o -iname '*signature*'
```

Apps may ship a manifest of expected resource hashes or verify downloaded config/signatures.

**5. Nested code verification**

Check whether frameworks/plugins/helpers are signed consistently:

```bash
codesign --verify --deep --strict --verbose=4 SomeApp.app
find SomeApp.app -type f \( -perm -111 -o -name '*.dylib' -o -name '*.bundle' -o -name '*.framework' \)
```

A developer concerned with tamper protection may verify nested code at runtime too.

**6. Runtime behavior**

Run the app normally, then run a copied/re-signed version and compare logs:

```bash
log stream --predicate 'process CONTAINS "AppName"' --style compact
```

Signs of detection may be messages like:

```text
integrity check failed
invalid signature
bundle modified
license validation failed
unexpected team identifier
```

But mature apps often avoid obvious log messages.

**7. Unity-specific signs**

For Unity apps, check:

```bash
find SomeApp.app -iname 'global-metadata.dat' -o -iname 'GameAssembly.dylib' -o -iname 'Assembly-CSharp.dll'
```

IL2CPP/native builds are harder to inspect casually than Mono builds. Tamper checks may live in native code, managed assemblies, Unity plugins, or server-side logic.

The practical conclusion is: you can detect **evidence** of tamper detection, especially signature checks, anti-debug checks, integrity hashes, and server validation. You generally cannot prove an app has none without full source or a very deep reverse-engineering pass.
