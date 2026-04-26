using System;
using System.Diagnostics;

class Program
{
    static void Main()
    {
        Stopwatch sw = Stopwatch.StartNew();
        int limit = 10_000_000;
        
        bool[] isPrime = new bool[limit + 1];
        Array.Fill(isPrime, true);
        isPrime[0] = false;
        isPrime[1] = false;

        for (int p = 2; p * p <= limit; p++)
        {
            if (isPrime[p])
            {
                for (int i = p * p; i <= limit; i += p)
                    isPrime[i] = false;
            }
        }

        int count = 0;
        for (int i = 0; i <= limit; i++)
        {
            if (isPrime[i]) count++;
        }

        sw.Stop();
        
        Console.WriteLine("--- C# (Native AOT) ---");
        Console.WriteLine($"So nguyen to tim duoc (<{limit}): {count}");
        Console.WriteLine($"Thoi gian chay: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine("Nhan Enter de thoat...");
        Console.ReadLine();
    }
}
