import argparse
import os
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from enum import StrEnum
from typing import List

import dbus

APP_NAME = "btctl"


def terminate(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def error(message):
    notify(message, {"urgency": 2})


def notify(message, hints={}):
    notify_interface = dbus.Interface(
        dbus.SessionBus().get_object(
            "org.freedesktop.Notifications", "/org/freedesktop/Notifications"
        ),
        "org.freedesktop.Notifications",
    )
    notify_interface.Notify(
        APP_NAME, 0, "dialog-information", "Bluetooth", message, [], hints, 5000
    )


class Property(StrEnum):
    PAIRED = "Paired"
    CONNECTED = "Connected"


@dataclass
class Config:
    launcher: List[str]

    @staticmethod
    def default():
        return Config(launcher=["fuzzel", "--dmenu", "--index"])

    @staticmethod
    def override(config, overrides):
        def ensure_empty(options):
            if options:
                terminate(f"Unrecognized configuration options: {options}")

        if launcher := overrides.pop("launcher", None):
            if command := launcher.pop("command", None):
                config.launcher = command
            ensure_empty(launcher)
        ensure_empty(overrides)
        return config

    @staticmethod
    def load():
        default = Config.default()
        config_dir = os.environ.get("XDG_CONFIG_HOME")
        if not config_dir:
            home = os.environ.get("HOME")
            if home:
                config_dir = os.path.join(home, ".config")
            else:
                return default

        try:
            config_path = os.path.join(config_dir, APP_NAME, "config.toml")
            with open(config_path, "rb") as f:
                config = tomllib.load(f)
        except FileNotFoundError:
            return default

        return Config.override(default, config)


@dataclass(frozen=True)
class Device:
    address: str
    name: str
    path: str

    def format(self) -> str:
        return f"{self.address} {self.name}"

    def interface(self) -> dbus.Interface:
        dev = dbus.SystemBus().get_object("org.bluez", self.path)
        return dbus.Interface(dev, "org.bluez.Device1")


class Manager:
    def __init__(self, config):
        self.config = config

    def show_menu(self, devices):
        process = subprocess.run(
            self.config.launcher,
            input=devices,
            text=True,
            capture_output=True,
        )
        if process.returncode:
            terminate(f"Launcher exited with code {process.returncode}")
        return process.stdout.strip()

    def select_device(self, prop: Property):
        manager = dbus.Interface(
            dbus.SystemBus().get_object("org.bluez", "/"),
            "org.freedesktop.DBus.ObjectManager",
        )
        objects = manager.GetManagedObjects()

        devices = []
        for path, interfaces in objects.items():
            device = interfaces.get("org.bluez.Device1")
            if device and device.get(prop):
                devices.append(Device(device.get("Address"), device.get("Name"), path))

        out = self.show_menu("\n".join(d.format() for d in devices))
        if not out:
            terminate("Nothing was selected")

        try:
            i = int(out)
        except ValueError:
            terminate("Launcher returned a non-integer")

        if not 0 <= i < len(devices):
            terminate("Launcher returned an index outside of range")

        return devices[i]

    def connect(self):
        device = self.select_device(Property.PAIRED)

        try:
            device.interface().Connect()
            notify(f"Connected to {device.name}")
        except dbus.exceptions.DBusException as e:
            unavailable_messages = [
                "br-connection-page-timeout",
                "br-connection-create-socket",
            ]
            if (
                e.get_dbus_name() == "org.freedesktop.DBus.Error.NoReply"
                or e.get_dbus_message() in unavailable_messages
            ):
                error(f"Device {device.name} is unavailable")
            elif e.get_dbus_message() == "br-connection-refused":
                error(f"Device {device.name} refused the connection")
            else:
                error(f"Failed to connect to {device.name}: {e.get_dbus_message()}")

    def disconnect(self):
        device = self.select_device(Property.CONNECTED)

        try:
            device.interface().Disconnect()
            notify(f"Disconnected from {device.name}")
        except dbus.exceptions.DBusException as e:
            error(f"Failed to disconnect from {device.name}: {e.get_dbus_message()}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["connect", "disconnect"])
    args = parser.parse_args()

    manager = Manager(Config.load())
    if args.action == "connect":
        manager.connect()
    elif args.action == "disconnect":
        manager.disconnect()


if __name__ == "__main__":
    main()
