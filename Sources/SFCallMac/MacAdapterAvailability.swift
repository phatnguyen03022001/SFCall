public enum MacAdapterAvailability {
    public static var isSupportedPlatform: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }
}
