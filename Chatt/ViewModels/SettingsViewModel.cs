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

        public SettingsViewModel(SettingsView contentPage)
        {
            ContentPage = contentPage;
        }
        public ICommand GoHome => new Command(async (object obj) => { await ContentPage.Window.Navigation.PopModalAsync(); });
    }
}
