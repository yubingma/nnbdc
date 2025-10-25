package beidanci.service.security;

public enum EncodingAlgorithm {

    NOOP("noop"), MD5("MD5"), SHA1("SHA-1"), SHA256("SHA-256");

    private final String alg;

    EncodingAlgorithm(String alg) {
        this.alg = alg;
    }

    public String getValue() {
        return this.alg;
    }

    @Override
    public String toString() {
        return getValue();
    }
}
