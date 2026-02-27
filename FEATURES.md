# What is Syncal?

Syncal is an online platform tool to help people find a common available slot in their agendas.

## Features
### Loginless
Users can fill in their availability slots just by providing their own name. The name is used as a key in the database and is case insensitive.

This is both a feature and a way to focus on features that truly deliver value before bloating the software with unnecessary features.

### Inquiries

An inquiry has a title, a start date and an end date. Only admins can create an inquiry.

### Multiple Timezones
Syncal works with multiple timezones, and it automatically detects the users current timezone to display the dates and the intersections correctly.
Also, because some people use VPNs, Syncal allows users to change their current timezones at any time.
### No pre-established time blocks
Unlike Rallly, Doodle or Cal.com, users are free to enter their availability without any previously established timeslots.
The responsibility to find the intersections belongs to the software, and not to the users.

### Replicate availability
Users can define their availability for one day, and then replicate that to one or more days.

### Multiple Inquiries

Every inquiry gets a secret link like: syncal.mariomelo.com/UUID, and you can make multiple inquiries at any given time.

### Inquiry Dashboard
By accessing the inquiry link you'll see a list of the intersections. You can filter and order it by **minimum intersection time** and **participants available in this intersection**.

### Admin Panel
There's no login, so the admins use a special name defined in the environment variable ADMIN_USERS and their names are listed in ADMIN_USERS_DISPLAY_NAMES.
These variables might a have a single name or a list of names separated by commas. The lists need to have the same size, as the index will be used to find the admin users display names.

### Admin Rights
Admins can remove people from an inquiry.

## Tech Stack
- Elixir
- Phoenix LiveView
- PostgreSQL
- DaisyUI
