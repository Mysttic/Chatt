using Chatt.Entities.Model;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Repositories
{
    public class SettingsRepository : BaseRepository<SettingsModel>
    {
        public SettingsRepository() : base()
        {
        }

        public SettingsModel GetSettings()
        {
            return connection.Table<SettingsModel>().FirstOrDefault();
        }
    }
}
