# encoding: binary
# frozen_string_literal: true

module RbNaCl
  module Boxes
    # The Box class boxes and unboxes messages between a pair of keys
    #
    # This class uses the given public and secret keys to derive a shared key,
    # which is used with the nonce given to encrypt the given messages and
    # decrypt the given ciphertexts.  The same shared key will generated from
    # both pairing of keys, so given two keypairs belonging to alice (pkalice,
    # skalice) and bob(pkbob, skbob), the key derived from (pkalice, skbob) with
    # equal that from (pkbob, skalice).  This is how the system works:
    #
    # @example
    #   # On bob's system
    #   bobkey = RbNaCl::PrivateKey.generate
    #   #=> #<RbNaCl::PrivateKey ...>
    #
    #   # send bobkey.public_key to alice
    #   # receive alice's public key, alicepk
    #   # NB: This is actually the hard part of the system.  How to do it securely
    #   # is left as an exercise to for the reader.
    #   alice_pubkey = "..."
    #
    #   # make a box
    #   alicebob_box = RbNaCl::Box.new(alice_pubkey, bobkey)
    #   #=> #<RbNaCl::Box ...>
    #
    #   # encrypt a message to alice
    #   cipher_text = alicebob_box.box("A bad example of a nonce", "Hello, Alice!")
    #   #=> "..." # a string of bytes, 29 bytes long
    #
    #   # send ["A bad example of a nonce", cipher_text] to alice
    #   # note that nonces don't have to be secret
    #   # receive [nonce, cipher_text_to_bob] from alice
    #
    #   # decrypt the reply
    #   # Alice has been a little more sensible than bob, and has a random nonce
    #   # that is too fiddly to type here.  But there are other choices than just
    #   # random
    #   plain_text = alicebob_box.open(nonce, cipher_text_to_bob)
    #   #=> "Hey there, Bob!"
    #
    #   # we have a new message!
    #   # But Eve has tampered with this message, by flipping some bytes around!
    #   # [nonce2, cipher_text_to_bob_honest_love_eve]
    #   alicebob_box.open(nonce2, cipher_text_to_bob_honest_love_eve)
    #
    #   # BOOM!
    #   # Bob gets a RbNaCl::CryptoError to deal with!
    #
    # It is VITALLY important that the nonce is a nonce, i.e. it is a number used
    # only once for any given pair of keys.  If you fail to do this, you
    # compromise the privacy of the the messages encrypted.  Also, bear in mind
    # the property mentioned just above. Give your nonces a different prefix, or
    # have one side use an odd counter and one an even counter.  Just make sure
    # they are different.
    #
    # The ciphertexts generated by this class include a 16-byte authenticator which
    # is checked as part of the decryption.  An invalid authenticator will cause
    # the unbox function to raise.  The authenticator is not a signature.  Once
    # you've looked in the box, you've demonstrated the ability to create
    # arbitrary valid messages, so messages you send are repudiable.  For
    # non-repudiable messages, sign them before or after encryption.
    class Curve25519XSalsa20Poly1305
      extend Sodium

      sodium_type      :box
      sodium_primitive :curve25519xsalsa20poly1305
      sodium_constant  :NONCEBYTES
      sodium_constant  :ZEROBYTES
      sodium_constant  :BOXZEROBYTES
      sodium_constant  :BEFORENMBYTES
      sodium_constant  :PUBLICKEYBYTES
      sodium_constant  :SECRETKEYBYTES, :PRIVATEKEYBYTES

      sodium_function :box_curve25519xsalsa20poly1305_beforenm,
                      :crypto_box_curve25519xsalsa20poly1305_beforenm,
                      [:pointer, :pointer, :pointer]

      sodium_function :box_curve25519xsalsa20poly1305_open_afternm,
                      :crypto_box_curve25519xsalsa20poly1305_open_afternm,
                      [:pointer, :pointer, :ulong_long, :pointer, :pointer]

      sodium_function :box_curve25519xsalsa20poly1305_afternm,
                      :crypto_box_curve25519xsalsa20poly1305_afternm,
                      [:pointer, :pointer, :ulong_long, :pointer, :pointer]

      # Create a new Box
      #
      # Sets up the Box for deriving the shared key and encrypting and
      # decrypting messages.
      #
      # @param public_key [String,RbNaCl::PublicKey] The public key to encrypt to
      # @param private_key [String,RbNaCl::PrivateKey] The private key to encrypt with
      #
      # @raise [RbNaCl::LengthError] on invalid keys
      #
      # @return [RbNaCl::Box] The new Box, ready to use
      def initialize(public_key, private_key)
        @public_key   = public_key.is_a?(PublicKey) ? public_key : PublicKey.new(public_key)
        @private_key  = private_key.is_a?(PrivateKey) ? private_key : PrivateKey.new(private_key)
        raise IncorrectPrimitiveError unless @public_key.primitive == primitive && @private_key.primitive == primitive
      end

      # Encrypts a message
      #
      # Encrypts the message with the given nonce to the keypair set up when
      # initializing the class.  Make sure the nonce is unique for any given
      # keypair, or you might as well just send plain text.
      #
      # This function takes care of the padding required by the NaCL C API.
      #
      # @param nonce [String] A 24-byte string containing the nonce.
      # @param message [String] The message to be encrypted.
      #
      # @raise [RbNaCl::LengthError] If the nonce is not valid
      #
      # @return [String] The ciphertext without the nonce prepended (BINARY encoded)
      def box(nonce, message)
        Util.check_length(nonce, nonce_bytes, "Nonce")
        msg = Util.prepend_zeros(ZEROBYTES, message)
        ct  = Util.zeros(msg.bytesize)

        success = self.class.box_curve25519xsalsa20poly1305_afternm(ct, msg, msg.bytesize, nonce, beforenm)
        raise CryptoError, "Encryption failed" unless success

        Util.remove_zeros(BOXZEROBYTES, ct)
      end
      alias encrypt box

      # Decrypts a ciphertext
      #
      # Decrypts the ciphertext with the given nonce using the keypair setup when
      # initializing the class.
      #
      # This function takes care of the padding required by the NaCL C API.
      #
      # @param nonce [String] A 24-byte string containing the nonce.
      # @param ciphertext [String] The message to be decrypted.
      #
      # @raise [RbNaCl::LengthError] If the nonce is not valid
      # @raise [RbNaCl::CryptoError] If the ciphertext cannot be authenticated.
      #
      # @return [String] The decrypted message (BINARY encoded)
      def open(nonce, ciphertext)
        Util.check_length(nonce, nonce_bytes, "Nonce")
        ct = Util.prepend_zeros(BOXZEROBYTES, ciphertext)
        message = Util.zeros(ct.bytesize)

        success = self.class.box_curve25519xsalsa20poly1305_open_afternm(message, ct, ct.bytesize, nonce, beforenm)
        raise CryptoError, "Decryption failed. Ciphertext failed verification." unless success

        Util.remove_zeros(ZEROBYTES, message)
      end
      alias decrypt open

      # The crypto primitive for the box class
      #
      # @return [Symbol] The primitive used
      def primitive
        self.class.primitive
      end

      # The nonce bytes for the box class
      #
      # @return [Integer] The number of bytes in a valid nonce
      def self.nonce_bytes
        NONCEBYTES
      end

      # The nonce bytes for the box instance
      #
      # @return [Integer] The number of bytes in a valid nonce
      def nonce_bytes
        NONCEBYTES
      end

      private

      def beforenm
        @_key ||= begin
          key = Util.zeros(BEFORENMBYTES)
          success = self.class.box_curve25519xsalsa20poly1305_beforenm(key, @public_key.to_s, @private_key.to_s)
          raise CryptoError, "Failed to derive shared key" unless success
          key
        end
      end
    end
  end
end
