use v6.d;

role Pwmgr::Crypt {
	method index-path(--> Str) {...}; # XXX rename this
	method encrypted-read(IO $path --> Str) {...};
	method encrypted-write(IO $path, Str $data) {...};
}

class Pwmgr::Crypt::GPG does Pwmgr::Crypt {
	method index-path {
		return 'index';
	}

	method encrypted-read(IO $path) {
		my @gpg = 'gpg2', '--quiet', '--decrypt', $path;
		my $proc = run(|@gpg, :out) // die "Failed to run gpg2: @gpg[]";
		my $data = $proc.out.slurp(:close);
		$proc.sink;
		return $data;
	}

	method encrypted-write(IO $path, Str $data) {
		my $fh = open $path, :w;
		my @gpg = 'gpg2', '--quiet', '--encrypt', '--default-recipient-self';
		my $proc = run(|@gpg, :in, :out($fh)) // die "Failed to run gpg2: @gpg[]";
		$proc.in.spurt($data, :close);
		$proc.sink;
	}
}

class Pwmgr::Crypt::SecretBox does Pwmgr::Crypt {
	use Crypt::Argon2::DeriveKey;
	use Crypt::Random;
	use Crypt::TweetNacl::SecretKey;
	use JSON::Tiny;
	use Terminal::Getpass;

	constant SALT_LENGTH = 16;
	has $!passphrase = Nil;
	has $!salt = Nil;
	my $default-parameters = {
		t_cost => 3,
		m_cost => 32*1024,
		parallelism => 1,
		hashlen => 32,
	};

	method !derive-key($passphrase, :$parameters is copy = $default-parameters) {
		my Buf $salt;
		if $parameters<salt>:exists {
			$salt = from-hexstr($parameters<salt>);
		} else {
			$salt = crypt_random_buf(SALT_LENGTH);
		}
		$parameters<salt> = $salt;

		my $meta = Argon2-meta.new(|$parameters);
		my $key = argon2-derive-key($passphrase, $meta);

		$parameters<salt> = to-hexstr($parameters<salt>);
		return $key, $parameters;
	}

	method !get-secret {
		unless $!passphrase {
			$!passphrase = getpass("Enter passphrase: ");
		}

		return $!passphrase;
	}

	method index-path {
		return 'index.json';
	}

	method encrypted-read(IO $path --> Str) {
		my $fh = open $path;

		my $message = from-json($fh.slurp());

		my $passphrase = self!get-secret;
		my ($key, $) = self!derive-key($passphrase, :parameters($message<kdf>));
		die "KDF returned wrong number of bytes" if $key.list.elems != 32;

		use Crypt::TweetNacl::Constants;
		use NativeCall;
		my $secret = CArray[int8].new: $key.list;
		# XXX: why do I have to manually prepend zeroes here?
		my $ciphertext = CArray[int8].new: from-hexstr(("00" x CRYPTO_SECRETBOX_BOXZEROBYTES) ~ $message<data>);
		my $nonce = CArray[int8].new: from-hexstr($message<nonce>);

		my $csbo = CryptoSecretBoxOpen.new(sk => $secret);
		my $data = $csbo.decrypt($ciphertext, $nonce);

		return $data.decode;
	}

	my sub from-hexstr(Str $encoded --> Buf) {
		Buf.new: $encoded.comb(/../).map: {:16($_)};
	}

	my sub to-hexstr(Blob $bytes --> Str) {
		$bytes.list.fmt('%02x', '');
	}

	method encrypted-write(IO $path, Str $data) {
		my $fh = open $path, :w;

		my $passphrase = self!get-secret;
		my ($key, $kdf) = self!derive-key($passphrase);
		die "KDF returned wrong number of bytes" if $key.elems != 32;

		use NativeCall;
		my $secret = CArray[int8].new: $key.list;

		my $csb = CryptoSecretBox.new(sk => $secret);
		my $ciphertext = $csb.encrypt($data.encode);
		my $out = {
			data => to-hexstr(Blob.new($ciphertext.data.list)),
			nonce => to-hexstr(Blob.new($ciphertext.nonce.list)),
			kdf => $kdf,
		};
		$fh.spurt(to-json($out), :close);
	}
}
