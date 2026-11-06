# Message for Dell

Copy the subject and body below into the case form, the community post and any email.
Nothing else needs editing.

---

**Subject**

```
G15 5530 (service tag CYFY434) - switching the display to the NVIDIA GPU leaves an extra monitor device and the machine stutters
```

**Body**

```
Hello,

I have a Dell G15 5530, service tag CYFY434, BIOS 1.36.0. I would like to report
something I have been able to measure reliably.

When I set Display Mode to "NVIDIA GPU only" in NVIDIA Control Panel, or let Advanced
Optimus move the panel to the RTX 4060, Windows ends up with two monitor devices for the
one built-in panel. While that is the case, dwm.exe uses 31 to 54 percent of a single CPU
core and the machine stalls. Typing, mouse movement and game frame pacing all break up,
sometimes for about a second at a time.

Going back to Optimus, or disabling and re-enabling the Intel display adapter, makes the
extra device disappear and dwm drops to between 0 and 2 percent. The two numbers always
move together, and it reproduces every time.

I have tried to rule out my own setup. I installed Dell's own graphics package A17
(32.0.16.1687) with the matching NVPCF 32.0.16.1534, after removing NVIDIA's newer
generic driver, and the behaviour is identical. The BIOS is already 1.36.0, which is the
newest listed for this model. It also happens with the machine idle on the desktop with
nothing running, and the GPU sits between 47 and 72 C, so it is not heat or load.

There is a second part that makes this difficult to live with. The extra monitor device
that causes the stutter is also the only thing that provides display brightness here. If I
disable it to get a usable machine, the brightness slider disappears and the Fn brightness
keys stop working. So I can have a laptop that stutters, or a laptop whose brightness I
cannot change.

I already have a workaround, so I am not asking for one. What I would like to know is
whether this is a known issue on the G15 5530, and whether a BIOS, EC or driver update is
expected to change it. I can send the full measurements, the monitor device enumeration
and the registry connectivity records if that is useful.

Thank you,
Md. Morshed Milton
Service tag: CYFY434
```

---

## Do not add these

- "Please fix it by doing X" — how they fix it is their call.
- Anything about the tools I built. They are irrelevant to Dell and invite closing the case.
- "I paid a lot of money" — it does not move a support queue.
- Any mention of tcc-g15, AWCC, or the registry edits I made. Only facts about the stock
  machine and Dell's own drivers.

## The four numbers to have ready if they call

```
1 monitor  + dwm ~2%   = Optimus, fine
2 monitors + dwm ~32%  = panel on NVIDIA, fault
clearing the duplicate -> dwm drops, brightness interface goes from 1 to 0
same on Dell driver A17 + NVPCF 615.34, so it is not my driver choice
```
