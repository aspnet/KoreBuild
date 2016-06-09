using System;

namespace Microsoft.AspNetCore.Build
{
    public static class Program
    {
        public static int Main(string[] args)
        {
            Console.Error.WriteLine("Only needed to work around the fact that you can't publish a library :(");
            return 1;
        }
    }
}
