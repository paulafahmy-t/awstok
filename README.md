# AWS Token Utility (awstok)

`awstok` is a command-line tool for macOS designed to simplify the management and refresh of AWS CodeArtifact tokens for NuGet. It is designed to be installed via Homebrew and run as a background service.

## Features

- **Simple Commands**: A small set of commands to manage the entire token lifecycle.
- **Interactive Login**: Supports interactive login for AWS accounts that require MFA.
- **Automated Refresh**: Can run non-interactively, making it suitable for scheduled tasks.
- **GUI Prompts**: On timeout or failure, it can display a native macOS dialog to prompt for an interactive login.
- **Desktop Notifications**: Provides native macOS notifications for success or failure events.
- **Homebrew Service**: Includes a Homebrew service file to automatically refresh the token daily.

## Prerequisites

Before installing, please ensure you have the following dependencies installed:

- [AWS CLI](https://aws.amazon.com/cli/) (`awscli`)
- [GNU Core Utilities](https://formulae.brew.sh/formula/coreutils) (`coreutils`) - for `gtimeout`
- [.NET SDK](https://dotnet.microsoft.com/download) (`dotnet`)
- [saml2aws](https://github.com/Versent/saml2aws) (`saml2aws`)

## Installation

You can install `awstok` using Homebrew.

1.  **Tap the repository**:
    First, add the custom tap.
    ```sh
    brew tap paulafahmy-t/tools
    ```

2.  **Install the tool**:
    Now, install `awstok` from the tap.
    ```sh
    brew install awstok
    ```

## Usage

Once installed, you can use the following commands:

- `awstok login`
  Runs an interactive login flow, prompting for MFA. This is the best command to run first.

- `awstok refresh`
  Attempts a non-interactive refresh. Ideal for automated scripts.

- `awstok check`
  A safe refresh attempt with a 2-minute timeout. If it fails or times out, it will show a GUI prompt asking to run the interactive login.

- `awstok gt`
  Gets and prints the current token stored in your NuGet configuration.

- `awstok help`
  Displays the help message.

## Scheduled Refresh Service

When you install `awstok` via Homebrew, it automatically configures a background service.

- **What it does**: The service runs `awstok refresh` automatically every day at 9:30 AM.
- **Logs**: Logs from the automated runs are stored at `$(brew --prefix)/var/log/awstok.log`.
- **Managing the service**:
  - To start the service manually (it starts by default after installation):
    ```sh
    brew services start awstok
    ```
  - To stop the service:
    ```sh
    brew services stop awstok
    ```

## Upgrage

```sh
brew update
brew upgrade awstok
brew services restart awstok
```

## Uninstall

```sh
brew services stop awstok
brew uninstall awstok
```