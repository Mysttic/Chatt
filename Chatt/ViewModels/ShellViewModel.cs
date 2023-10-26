using Chatt.Views;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Chatt.ViewModels
{
    public class ShellViewModel
    {
        AppShell shell;
        public ShellViewModel(AppShell appShell)
        {
            shell = appShell;
        }
        public ICommand GoSettings => new Command(async (object obj) => { await shell.Window.Navigation.PushModalAsync(new SettingsView()); });


    }
}
