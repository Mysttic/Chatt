using Greet;
using System.Net.NetworkInformation;
using System.Net;
using System.Net.Sockets;

namespace Chatt;

public partial class ChattPage : ContentPage
{
	public ChattPage()
	{
		InitializeComponent();
	}
    const string host = "127.0.0.1";
    private void Button_Clicked(object sender, EventArgs e)
    {
        ClientsEditor.Text = "";
        ButtonSearch.Text = "Searching";   
        var greeting = new Greeting()
        {
            FirstName = "Dante",
            LastName = "Devilry"
        };

        var greetingRequest = new GreetingRequest() { Greeting = greeting };
        using (TcpClient tcpClient = new TcpClient())
        {
            for (int i = 50050; i <= 50060; i++)
            {
                //if (IsPortOpen(host, i, new TimeSpan(0, 0, 5)))
                if (PortInUse(i))
                {
                    ClientsEditor.Text += host + i + "\n";
                    SemanticScreenReader.Announce(ClientsEditor.Text);
                }
                //GreetingService.GreetingServiceClient client = MauiProgram.CreateGrpcClient("127.0.0.1", i);
                //try
                //{
                //    var greetingResponse = client.Greet(greetingRequest);
                //    if (greetingResponse != null)
                //    {
                //        ClientsEditor.Text += "127.0.0.1" + i + "\n";
                //    }
                //} catch (Exception ex) { }
            }
        }
        //var greeting = new Greeting()
        //{
        //    FirstName = "Dante",
        //    LastName = "Devilry"
        //};

        //var greetingRequest = new GreetingRequest() { Greeting = greeting };
        //var greetingResponse = MauiProgram.greetingServiceClient.Greet(greetingRequest);
        ButtonSearch.Text = "Search clients";
        
    }

    bool IsPortOpen(string host, int port, TimeSpan timeout)
    {
        try
        {
            using (var client = new TcpClient())
            {
                var result = client.BeginConnect(host, port, null, null);
                var success = result.AsyncWaitHandle.WaitOne(timeout);
                client.EndConnect(result);
                return success;
            }
        }
        catch (SocketException ex)
        {
            return false;
        }
    }

    public static bool PortInUse(int port)
    {
        bool inUse = false;

        IPGlobalProperties ipProperties = IPGlobalProperties.GetIPGlobalProperties();
        IPEndPoint[] ipEndPoints = ipProperties.GetActiveTcpListeners();


        foreach (IPEndPoint endPoint in ipEndPoints)
        {
            if (endPoint.Port == port)
            {
                inUse = true;
                break;
            }
        }


        return inUse;
    }
}