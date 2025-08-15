package cli.utils

@When[os == "Windows"]
foreign func getch(): IntNative

@When[os == "Windows"]
public func getchar(): IntNative {
    let c = unsafe {
        getch()
    }

    return c
}
