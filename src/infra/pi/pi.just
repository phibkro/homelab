# Lint and syntax-check the Pi appliance.
@check:
    devenv shell -- check

# Apply safe automatic lint fixes to the Pi appliance.
@fix:
    devenv shell -- fix

# Converge twice in a disposable ARM64 Debian QEMU guest.
@test:
    devenv shell -- test

# Preview the production convergence without changing the Pi.
@plan:
    devenv shell -- secretspec run --profile production --scope deployment -- bash scripts/run-production.sh plan

# Read the Caddyfile mounted in the running production container through the
# generated inventory and a caller-supplied pinned host-key file.
@inspect-caddy:
    devenv shell -- bash scripts/run-production.sh inspect-caddy

# Converge the physical Pi after exact target confirmation.
@deploy:
    devenv shell -- secretspec run --profile production --scope deployment -- bash scripts/run-production.sh deploy

# Enroll the physical Pi into Tailscale after exact target confirmation.
@enroll:
    devenv shell -- secretspec run --profile production --scope enrollment -- bash scripts/run-production.sh enroll

# Check or interactively populate the production SecretSpec profile.
@secrets:
    devenv shell -- secrets
