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
    devenv shell -- secretspec run --profile production -- bash scripts/run-production.sh plan

# Converge the physical Pi after exact target confirmation.
@deploy:
    devenv shell -- secretspec run --profile production -- bash scripts/run-production.sh deploy

# Check or interactively populate the production SecretSpec profile.
@secrets:
    devenv shell -- secrets
