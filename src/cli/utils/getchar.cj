package cli.cli.utils

@When[os == "Windows"]
foreign func getch(): IntNative

public func getchar(): IntNative {
    let c = unsafe { 
        getch()
    }

    return c
}
