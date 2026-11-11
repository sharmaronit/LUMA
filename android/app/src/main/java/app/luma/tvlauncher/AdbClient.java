/*
 * Luma
 * Copyright (C) 2026 Ronit Sharma
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */
package app.luma.tvlauncher;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;

/**
 * A small ADB client that talks to the TV's own debugging service on
 * localhost. It lets Luma run the few package-manager commands the cleaner
 * needs without a computer. Only the classic TCP transport (port 5555) is
 * supported; the paired "Wireless debugging" transport is not.
 */
final class AdbClient implements Closeable {
    /** The TV is not listening for ADB on this port. */
    static final class Unreachable extends IOException {
        Unreachable(String message) { super(message); }
    }

    /** The user has not allowed this app on the "Allow USB debugging?" prompt. */
    static final class Unauthorized extends IOException {
        Unauthorized(String message) { super(message); }
    }

    private static final int CNXN = 0x4e584e43, AUTH = 0x48545541, OPEN = 0x4e45504f,
            OKAY = 0x59414b4f, CLSE = 0x45534c43, WRTE = 0x45545257;
    private static final int VERSION = 0x01000000, MAX_DATA = 4096;
    private static final int AUTH_TOKEN = 1, AUTH_SIGNATURE = 2, AUTH_PUBLIC_KEY = 3;
    private static final int KEY_WORDS = 64;
    // ASN.1 DigestInfo header for SHA-1; adbd expects the token signed as a SHA-1 digest.
    private static final byte[] SHA1_PREFIX = {
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};
    private static final String PREFS = "luma_adb", PRIVATE = "private", PUBLIC = "public";

    private final Socket socket;
    private final InputStream in;
    private final OutputStream out;
    private int nextLocalId = 1;

    private record Message(int command, int arg0, int arg1, byte[] data) {}

    private AdbClient(Socket socket) throws IOException {
        this.socket = socket;
        in = socket.getInputStream();
        out = socket.getOutputStream();
    }

    /**
     * Connects and authenticates. The first time, the TV shows its "Allow USB
     * debugging?" prompt and this waits up to {@code approvalMs} for an answer.
     */
    static AdbClient connect(Context context, int port, int approvalMs) throws Exception {
        return connect(context, port, approvalMs, true);
    }

    /**
     * With {@code offerKey} false the TV is never asked to approve this app:
     * the connection only succeeds if it was approved before.
     */
    static AdbClient connect(Context context, int port, int approvalMs, boolean offerKey) throws Exception {
        Socket socket = new Socket();
        try {
            socket.connect(new InetSocketAddress("127.0.0.1", port), 3000);
        } catch (IOException e) {
            throw new Unreachable(String.valueOf(e.getMessage()));
        }
        AdbClient client = new AdbClient(socket);
        try {
            client.handshake(keys(context), approvalMs, offerKey);
            return client;
        } catch (Exception e) {
            client.close();
            throw e;
        }
    }

    private void handshake(KeyPair keys, int approvalMs, boolean offerKey) throws Exception {
        socket.setSoTimeout(8000);
        send(CNXN, VERSION, MAX_DATA, "host::\0".getBytes(StandardCharsets.UTF_8));
        boolean signed = false;
        while (true) {
            Message message;
            try {
                message = read();
            } catch (java.net.SocketTimeoutException e) {
                throw new Unauthorized("No answer to the debugging prompt");
            } catch (EOFException e) {
                throw new Unauthorized("The TV closed the connection");
            }
            if (message.command == CNXN) {
                socket.setSoTimeout(30000);
                return;
            }
            if (message.command != AUTH || message.arg0 != AUTH_TOKEN) continue;
            if (!signed) {
                signed = true;
                send(AUTH, AUTH_SIGNATURE, 0, sign(keys.getPrivate(), message.data));
            } else if (!offerKey) {
                throw new Unauthorized("Not approved on this TV");
            } else {
                // The key is unknown to the TV: offer it and wait for the user.
                socket.setSoTimeout(approvalMs);
                send(AUTH, AUTH_PUBLIC_KEY, 0, adbPublicKey((RSAPublicKey) keys.getPublic()));
            }
        }
    }

    /** Runs one shell command and returns everything it printed. */
    String shell(String command) throws IOException {
        int local = nextLocalId++;
        send(OPEN, local, 0, ("shell:" + command + "\0").getBytes(StandardCharsets.UTF_8));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        int remote = 0;
        while (true) {
            Message message = read();
            if (message.arg1 != local) continue;
            switch (message.command) {
                case OKAY -> remote = message.arg0;
                case WRTE -> {
                    remote = message.arg0;
                    output.write(message.data);
                    send(OKAY, local, remote, new byte[0]);
                }
                case CLSE -> {
                    if (remote != 0) send(CLSE, local, remote, new byte[0]);
                    return output.toString("UTF-8");
                }
                default -> { }
            }
        }
    }

    private void send(int command, int arg0, int arg1, byte[] data) throws IOException {
        int sum = 0;
        for (byte b : data) sum += b & 0xff;
        ByteBuffer buffer = ByteBuffer.allocate(24 + data.length).order(ByteOrder.LITTLE_ENDIAN);
        buffer.putInt(command).putInt(arg0).putInt(arg1).putInt(data.length).putInt(sum).putInt(~command);
        buffer.put(data);
        out.write(buffer.array());
        out.flush();
    }

    private Message read() throws IOException {
        ByteBuffer header = ByteBuffer.wrap(readFully(24)).order(ByteOrder.LITTLE_ENDIAN);
        int command = header.getInt(), arg0 = header.getInt(), arg1 = header.getInt(), length = header.getInt();
        if (length < 0 || length > 1024 * 1024) throw new IOException("Bad ADB message");
        return new Message(command, arg0, arg1, readFully(length));
    }

    private byte[] readFully(int length) throws IOException {
        byte[] data = new byte[length];
        int offset = 0;
        while (offset < length) {
            int count = in.read(data, offset, length - offset);
            if (count < 0) throw new EOFException();
            offset += count;
        }
        return data;
    }

    @Override public void close() {
        try { socket.close(); } catch (IOException ignored) { }
    }

    private static byte[] sign(PrivateKey key, byte[] token) throws Exception {
        Signature signature = Signature.getInstance("NONEwithRSA");
        signature.initSign(key);
        signature.update(SHA1_PREFIX);
        signature.update(token);
        return signature.sign();
    }

    /** The public key in the layout adbd stores in its adb_keys file. */
    static byte[] adbPublicKey(RSAPublicKey key) {
        BigInteger n = key.getModulus();
        BigInteger r32 = BigInteger.ONE.shiftLeft(32);
        BigInteger r = BigInteger.ONE.shiftLeft(KEY_WORDS * 32);
        BigInteger rr = r.multiply(r).mod(n);
        BigInteger n0inv = r32.subtract(n.mod(r32).modInverse(r32));
        ByteBuffer buffer = ByteBuffer.allocate(8 + KEY_WORDS * 8 + 4).order(ByteOrder.LITTLE_ENDIAN);
        buffer.putInt(KEY_WORDS).putInt(n0inv.intValue());
        for (int i = 0; i < KEY_WORDS; i++) buffer.putInt(n.shiftRight(32 * i).intValue());
        for (int i = 0; i < KEY_WORDS; i++) buffer.putInt(rr.shiftRight(32 * i).intValue());
        buffer.putInt(key.getPublicExponent().intValue());
        String text = Base64.encodeToString(buffer.array(), Base64.NO_WRAP) + " luma@tv\0";
        return text.getBytes(StandardCharsets.UTF_8);
    }

    /** One key pair per install, so the TV only asks for permission once. */
    private static synchronized KeyPair keys(Context context) throws Exception {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String privateKey = prefs.getString(PRIVATE, null), publicKey = prefs.getString(PUBLIC, null);
        KeyFactory factory = KeyFactory.getInstance("RSA");
        if (privateKey != null && publicKey != null) {
            try {
                return new KeyPair(
                        factory.generatePublic(new X509EncodedKeySpec(Base64.decode(publicKey, Base64.NO_WRAP))),
                        factory.generatePrivate(new PKCS8EncodedKeySpec(Base64.decode(privateKey, Base64.NO_WRAP))));
            } catch (Exception ignored) {
                // Fall through and make a new pair.
            }
        }
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(KEY_WORDS * 32);
        KeyPair pair = generator.generateKeyPair();
        prefs.edit()
                .putString(PRIVATE, Base64.encodeToString(pair.getPrivate().getEncoded(), Base64.NO_WRAP))
                .putString(PUBLIC, Base64.encodeToString(pair.getPublic().getEncoded(), Base64.NO_WRAP))
                .apply();
        return pair;
    }
}
