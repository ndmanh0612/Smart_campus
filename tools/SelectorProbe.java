import java.nio.channels.Selector;

/** Isolates the JVM selector needed by Gradle, without starting an Android build. */
public class SelectorProbe {
    public static void main(String[] args) throws Exception {
        try (Selector selector = Selector.open()) {
            if (!selector.isOpen()) throw new IllegalStateException("Selector did not open");
            System.out.println("PASS: Java NIO Selector.open");
        }
    }
}
