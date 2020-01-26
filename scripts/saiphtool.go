package main

import (
	"bufio"
	//"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	//"io"
	"io/ioutil"
	"os"

	"golang.org/x/crypto/nacl/secretbox"
	"golang.org/x/crypto/argon2"
)

type KDFMeta struct {
	T_Cost uint32 `json:"t_cost"`
	M_Cost uint32 `json:"m_cost"`
	Parallelism uint8 `json:"parallelism"`
	HashLen uint32 `json:"hashlen"`
	Salt string `json:"salt"`
}

type Message struct {
	Nonce string `json:"nonce"`
	Data string `json:"data"`

	KDF KDFMeta `json:"kdf"`
}

func main() {
	var decryptOperation = flag.Bool("decrypt", false, "decrypt data rather than encrypt")
	//key := "616b00000000000000000000000000000000000000000000000000000000";
	var key = flag.String("key", "", "key as string")
	var filename = flag.String("filename", "", "filename")
	flag.Parse()
	if *decryptOperation {
		decrypt(*filename, *key)
	} else {
		encrypt(*filename, *key)
	}
}

func run_kdf(key string, meta KDFMeta) []byte {
	//abort fix me here!
	salt, err := hex.DecodeString(meta.Salt)
	if err != nil {
		panic(err)
	}
	return argon2.Key([]byte(key), salt, meta.T_Cost, meta.M_Cost, meta.Parallelism, meta.HashLen)
}

func decrypt(filename string, key string) {
	data, err := ioutil.ReadFile(filename)
	if err != nil {
		panic(err)
	}

	var m Message
	if err := json.Unmarshal(data, &m); err != nil {
		panic(err)
	}

	encrypted, err := hex.DecodeString(m.Data)
	if err != nil {
		panic(err)
	}

	secretKeyBytes := run_kdf(key, m.KDF)

	var secretKey [32]byte
	copy(secretKey[:], secretKeyBytes)

	nonceBytes, err := hex.DecodeString(m.Nonce)
	if err != nil {
		panic(err)
	}
	var nonceData [24]byte
	copy(nonceData[:], nonceBytes)

	fmt.Println("note, data length is", len(encrypted))
	fmt.Println(encrypted)
	fmt.Println("nonce:", nonceData)
	fmt.Println("secret:", secretKey)

	text, ok := secretbox.Open(nil, encrypted, &nonceData, &secretKey)
	if !ok {
		panic("decryption error")
	}
	fmt.Print(string(text))
}

func encrypt(filename string, key string) {
	reader := bufio.NewReader(os.Stdin)
	//fmt.Print("text: ")
	text, _ := reader.ReadBytes('\n')

	secretKeyBytes := run_kdf(key, KDFMeta{
		T_Cost: 3,
		M_Cost: 32*1024,
		Parallelism: 1,
		HashLen: 32,
		Salt: "",
	})

	var secretKey [32]byte
	copy(secretKey[:], secretKeyBytes)

	var nonce [24]byte
//	if _, err := io.ReadFull(rand.Reader, nonce[:]); err != nil {
//		panic(err)
//	}
	encrypted := secretbox.Seal(nil, text, &nonce, &secretKey)

	m := Message{}
	m.Nonce = hex.EncodeToString(nonce[:])
	m.Data = hex.EncodeToString(encrypted)

	out, err := json.Marshal(m)
	if err != nil {
		panic(err)
	}

	if err := ioutil.WriteFile(filename, out, 0600); err != nil {
		panic(err)
	}
}
