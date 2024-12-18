def main():
    print("1 - Effects window")
    print("2 - Interactive window")
    print("3 - Fractal Mandelbulb window")
    print("4 - Fractal Julia Set 3D")
    print("0 - Exit")
    option = input("Choose an option: ")

    while option not in ["0", "1", "2", "3", "4"]:
        print("Invalid option")
        option = input("Choose an option: ")

    if option == "1":
        from lib import WindowEffects as Window
    elif option == "2":
        from lib import WindowInteractive as Window
    elif option == "3":
        from lib import WindowMandelbulb as Window
    elif option == "4":
        from lib import WindowJuliaSet3D as Window
    elif option == "0":
        return

    window = Window()
    window.create_window()

    window.run()


if __name__ == "__main__":
    main()
