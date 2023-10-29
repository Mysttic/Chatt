using Chatt.Entities.Model;
using Chatt.UI;
using Chatt.Views;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Chatt.ViewModels
{
    public class UsersNearbyViewModel
    {
        UsersNearbyView ContentPage { get; set; }
        public SettingsModel SettingsModel { get; set; }

        public ObservableCollection<UserModel> Users { get; set; }

        public UsersNearbyViewModel(UsersNearbyView contentPage)
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
            Users = new ObservableCollection<UserModel>()
            {
                new UserModel()
                {
                    NickName = "Dyzio",
                    IpAddress = "127.0.0.1",
                    WelcomeMessage = "Hello there!"
                },
                new UserModel()
                {
                    NickName = "Hyzio",
                    IpAddress = "192.168.0.1",
                    WelcomeMessage = "Hi, im Hyzio please text me."

                },
                new UserModel()
                {
                    NickName = "Zyzio",
                    IpAddress = "1.1.0.1",
                    WelcomeMessage = ""
                }
            };
        }
    }
}
