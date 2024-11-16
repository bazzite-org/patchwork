.. SPDX-License-Identifier: GPL-2.0
.. include:: <isonum.txt>

=====================
S0ix Standby States
=====================

:Copyright: |copy| 2024 Antheas Kapenekakis

:Author: Antheas Kapenekakis <lkml@antheas.dev>

With the advent of modern mobile devices, users have become accustomed to instant
wake-up times and always-on connectivity. To meet these expectations, modern
standby was created, which is a standard that allows the platform to seamlessly
transition between an S3-like low-power idle state and a set of low power active
states, where connectivity is maintained, and the system is responsive to user
input. Current x86 hardware supports 5 different standby states, which are:
"Deepest run-time idle platform state" or "DRIPS" (S3-like), "Sleep", "Resume",
"Screen Off", and "Active".

The system begins in the "Active" state. Either due to user inactivity or
user action (e.g., pressing the power button), it transitions to the "Screen Off"
state. Afterwards, it is free to transition between the "Sleep", "DRIPS", and
"Screen Off" states until user action is received. Once that happens, the system
begins to transition to the "Active" state. From "DRIPS" or "Sleep", it
transitions to "Resume", where the Power Limit (PLx) is restored to its normal
level, to speed up finishing "Sleep". Then, it transitions to "Screen Off".
If on "Screen Off" or after the transition, the display is prepared to turn on
and the system transitions to "Active" alongside turning it on.

To maintain battery life, in the Windows implementation, the system is allocated
a maximum percentage of battery and time it can use while staying in idle states.
By default, this is 5% of battery or up to 2 days, where the system designer/OEM
is able to tweak these values. If the system exceeds either the battery
percentage or time limit, it enters Hibernation (S4), through a concept
called "Adaptive Hibernate".


S0ix Standby States
==================================
The following idle states are supported::

                 ↓→  <Hibernate (S4)>
    <DRIPS> ↔ <Sleep> ↔ <Screen Off> ↔ <Active>
        →       →  <Resume>  ↑

.. _s2idle_drips:

DRIPS
-----

The "Deepest run-time idle platform state" or "DRIPS" is the lowest power idle
state that the system can enter. It is similar to the S3 state, with the
difference that the system may wake up faster than S3 and due to a larger number
of interrupts (e.g., fingerprint sensor, touchpad, touchscreen). This state
is entered when the system is told to suspend to idle, through conventional
means (see :doc:`sleep states <sleep-states>`). The system can only transition
to "DRIPS" while it is in the "Sleep" state. If it is not, the kernel will
automatically transition to the "Sleep" state before beginning the suspend
sequence and restore the previous state afterwards. After the kernel has
suspended, the notifications LSP0 Entry and Exit are used.

.. _s2idle_sleep:

Sleep
-----

The "Sleep" state is a low power idle state where the kernel is fully active.
However, userspace has been partially frozen, particularly desktop applications,
and only essential "value adding" activities are allowed to run. This is not
enforced by the kernel and is the responsibility of userspace (e.g., systemd).
Hardware wise, the Sleep Entry and Exit firmware notifications are fired, which
may lower the Power Limit (PLx), pulse the suspend light, turn off the keyboard
lighting or disable a handheld device's gamepad. This state is associated with
the firmware notifications "Sleep Entry" and "Sleep Exit".

.. _s2idle_resume:

Resume
------

The "Resume" state is a faux "Sleep" state that is used to fire the Turn On
Display firmware notification when the system is in the "Sleep" state but
intends to turn on the display. It solves the problem of system designers
limiting the Power Limit (PLx) while the system is in the "Sleep" state causing
the system to wake up slower than desired. This firmware notification is used
to restore the normal Power Limit of the system, while having it stay in the
"Sleep" state.  As such, the system can only transition to the "Resume" state
while in the "Sleep" state and cannot re-transition to the "Sleep" state
afterwards.

.. _s2idle_screen_off:

Screen Off
----------

The "Screen Off" state is the state the system enters when all its displays
(virtual or real) turn off. It is used to signify the user is not actively
using the system. The associated firmware notifications of "Display On" and
"Display Off" are used by manufacturers to turn off certain hardware
components that are associated with the display being on, e.g., a handheld
device's controller and RGB. Windows implements a 5-second grace period
before firing this callback when the screen turns off due to inactivity.

.. _s2idle_active:

Active
------

Finally, the "Active" state is the default state of the system and the one it
has when it is turned on. It is the state where the system is fully operational,
the displays of the device are on, and the user is actively interacting with
the system.

Basic ``sysfs`` Interface for S0ix Standby transitions
=============================================================

The file :file:`/sys/power/standby` can be used to transition the system between
the different standby states. The file accepts the following values: ``active``,
``screen_off``, ``sleep``, and ``resume``. File writes will block until the
transition completes. It will return ``-EINVAL`` when asking for an unsupported
state or, e.g., requesting ``resume`` when not in the ``sleep`` state. If there
is an error during the transition, the transition will pause on the last
error-free state and return an error. The file can be read to retrieve the
current state (and potential ones) using the following format:
``[active] screen_off sleep resume``. The state "DRIPS" is omitted, as it is
entered through the conventional suspend to idle path and userspace will never
be able to see its value due to being suspended.

Before entering the "Screen Off" state or suspending, it is recommended that
userspace marks all CRTCs as inactive (DPMS). Otherwise, there will be a split
second where the display of the device is on, but the presentation of the system
is inactive (e.g., the power button pulses), which is undesirable.