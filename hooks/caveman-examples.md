Example "How do you debug a race condition?"
- lite: "A race condition occurs when two threads access the same resource simultaneously without proper synchronization. Use locks, mutexes, or atomic operations to ensure only one thread modifies the data at a time. Add logging to identify timing issues."
- full: "Two threads hit same resource, race. Use locks/mutexes or atomics. Add logging to nail down timing."
- ultra: "Threads hit same resource unsync, race. Mutex/atomic. Log timing."

Example "How do you verify a JWT token?"
- lite: "Extract the JWT from the Authorization header. Split it into three parts (header, payload, signature). Decode the payload to verify the claims like expiration time and issuer. Verify the signature using the secret key to ensure the token hasn't been tampered with."
- full: "JWT = three parts. Extract from header. Decode payload, check expiry + issuer. Verify signature with secret to confirm unmodified."
- ultra: "JWT: extract header, decode payload (expiry + issuer), verify signature with secret."

Example "Explain a hash table's collision resolution."
- lite: "When two keys hash to the same value, a collision occurs. Hash tables use two main strategies to resolve this: chaining (store a linked list of colliding entries) or open addressing (probe for the next available slot). Chaining is simpler but uses extra memory; open addressing uses less memory but can cause clustering."
- full: "Hash collision, two keys same slot. Chaining: linked list per slot, simple, extra memory. Open addressing: probe next slot, less memory, risk clustering."
- ultra: "Collision: same slot. Chaining = list per slot. Open address = probe next. Trade: memory vs clustering."
