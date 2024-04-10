using Yubico.YubiKey;
using Yubico.YubiKey.Piv;

internal class Program
{
    public static void Main(string[] args)
    {
        if (args.Length == 0) throw new ArgumentOutOfRangeException(nameof(args), "You have to provide a serial number for the security key");

        var targetKey = YubiKeyDevice.FindAll().FirstOrDefault(x => x.SerialNumber?.ToString() == args[0]) ?? throw new InvalidOperationException("There is no key attached with the specified serial number");
        using var PIVsession = new PivSession(targetKey);

        PIVsession.KeyCollector = (data) =>
        {
            if (data is null) return false;
            if (data.IsRetry) throw new InvalidOperationException("The yubikey PIN is not the default PIN. Reset the device first!");

            switch (data.Request)
            {
                case KeyEntryRequest.Release:
                    return true;
                case KeyEntryRequest.VerifyPivPin:
                    var currentPin = "123456"u8.ToArray();
                    data.SubmitValue(currentPin);
                    return true;
                default:
                    break;
            }

            return false;
        };
        PIVsession.SetPinOnlyMode(PivPinOnlyMode.PinProtected);
    }
}