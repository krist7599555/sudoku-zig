all:
	zig build-exe src/root.zig \
		-target wasm32-freestanding \
		-OReleaseSmall \
		-fno-entry