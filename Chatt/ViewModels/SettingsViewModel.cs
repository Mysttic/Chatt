using Chatt.Entities.Model;
using Chatt.Views;
using Microsoft.Maui.Controls;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Chatt.ViewModels
{
    public class SettingsViewModel
    {
        SettingsView ContentPage { get; set; }
        public SettingsModel SettingsModel { get; set; }

        public SettingsViewModel(SettingsView contentPage)
        {
            ContentPage = contentPage;
            Load();
        }
        public ICommand GoHome => new Command(async (object obj) => 
        { 
            await ContentPage.Window.Navigation.PopModalAsync(); 
        });

        async Task Load()
        {
            SettingsModel = new SettingsModel()
            {
                Nickname = "Dante devilry",
                WelcomeMessage = "Your welcome message",
                CustomPort = "50001-50010;50050;50075",
                ActivePort = "50001",
                IpFilter = "192.168.0.1-192.168.0.255;192.168.10.10;192.168.10.*",
                PortFilter = "50001-50010;50050;50075"
            };
            
        }
    }
}
