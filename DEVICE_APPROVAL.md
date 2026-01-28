# Device Approval Strategy for RDP + Tailscale

## TL;DR
- **GitHub runners**: Pre-authorized (auto-approve)
- **User devices**: Require manual approval
- Use **tags** to differentiate

## Setup

### 1. Tailscale Admin Settings

Go to [Admin Console > Settings > General](https://login.tailscale.com/admin/settings/general)

**Device authorization**:
- Toggle **Require device authorization** to **ON**
- This makes ALL new devices require approval by default

### 2. Auth Key Configuration

Create **two different auth keys**:

#### For GitHub Runners (Auto-approve)
1. Go to [Settings > Keys](https://login.tailscale.com/admin/settings/keys)
2. Generate auth key with:
   - **Reusable**: Yes
   - **Ephemeral**: No
   - **Pre-authorized**: Yes ✓ (bypasses device approval)
   - **Tags**: `tag:github-runner`
   - **Expiration**: 90 days or longer
3. Save as `TAILSCALE_AUTHKEY` secret

#### For Regular Users (Manual approval)
1. Generate auth key with:
   - **Reusable**: Yes
   - **Ephemeral**: No
   - **Pre-authorized**: No ✗ (requires admin approval)
   - **Tags**: None (user-based auth)
2. Share with team members

### 3. ACL Policy Example

```json
{
  "tagOwners": {
    "tag:github-runner": ["autogroup:admin"]
  },
  
  "acls": [
    // GitHub runners can be accessed by all authenticated users
    {
      "action": "accept",
      "src": ["autogroup:members"],
      "dst": ["tag:github-runner:*"]
    },
    
    // Users can access each other (after manual approval)
    {
      "action": "accept",
      "src": ["autogroup:members"],
      "dst": ["autogroup:members:*"]
    }
  ],
  
  "autoApprovers": {
    "routes": {
      "0.0.0.0/0": ["tag:github-runner"],
      "::/0": ["tag:github-runner"]
    }
  }
}
```

## How It Works

```
┌─────────────────────────────────────┐
│  Device Joins Tailscale             │
└──────────────┬──────────────────────┘
               │
               ▼
       ┌───────────────┐
       │  Has tag?     │
       └───┬───────┬───┘
           │       │
          Yes      No
           │       │
           │       ▼
           │   ┌────────────────────┐
           │   │ User-based device  │
           │   │ Requires approval  │
           │   └────────────────────┘
           │
           ▼
   ┌────────────────────┐
   │ Pre-authorized?    │
   └────┬───────────┬───┘
        │           │
       Yes          No
        │           │
        ▼           ▼
   Auto-approve   Needs approval
   (Runners)      (Tagged servers)
```

## Device Approval Dashboard

After enabling device authorization, you'll see pending devices at:
[Admin Console > Machines](https://login.tailscale.com/admin/machines)

Approve/reject devices individually or in bulk.

## Best Practices

1. **Always pre-authorize CI/CD runners** - they can't wait for human approval
2. **Require approval for user devices** - adds security layer
3. **Use descriptive hostnames** - makes approval easier (`gh-rdp-abc123` vs `DESKTOP-X7Y2`)
4. **Set auth key expiration** - rotate keys every 90 days
5. **Monitor approved devices** - review periodically and remove unused ones

## Workflow Impact

With pre-authorized auth key, the GitHub workflow:
- Connects immediately ✓
- No admin intervention needed ✓
- Maintains stable IP across chains ✓
- Automatically reconnects after 5.5 hours ✓

Regular users must:
- Install Tailscale
- Sign in with your auth key (non-pre-authorized)
- Wait for admin approval
- Then access the RDP session

## Security Considerations

| Setting | Security | Automation |
|---------|----------|------------|
| Pre-authorized = Yes | Lower | Higher |
| Pre-authorized = No | Higher | Lower |

For **GitHub runners**: Automation is critical, and the tag-based ACL provides sufficient security.

For **user devices**: Manual approval adds a verification layer before granting network access.
