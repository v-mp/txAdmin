const modulename = 'SocketRoom:Status';
import TxAdmin from "@core/txAdmin";
import { RoomType } from "../webSocket";
import consoleFactory from '@extras/console';
import { GlobalStatusType } from "@shared/socketioTypes";
const console = consoleFactory(modulename);


/**
 * Returns the fxserver's data
 */
const getinitialData = (txAdmin: TxAdmin): GlobalStatusType => {
    return {
        // @ts-ignore simplifying the status enum to a string
        discord: txAdmin.discordBot.wsStatus, //no push events, only passively updated
        server: {
            mutex: txAdmin.fxRunner?.currentMutex,
            status: txAdmin.healthMonitor.currentStatus || '??',
            process: txAdmin.fxRunner.getStatus(),
            name: txAdmin.globalConfig.serverName,
            players: txAdmin.playerlistManager.onlineCount,
            // @ts-ignore scheduler type narrowing id wrong because cant use "as const" in javascript
            scheduler: txAdmin.scheduler.getStatus(), //no push events, only passively updated
        },
    }
}


/**
 * The main room is joined automatically in every txadmin page (except solo ones)
 * It relays tx and server status data.
 * 
 * NOTE: 
 * - active push event for HealthMonitor, HostData, fxserver process
 * - passive update for discord status, scheduler
 * - the passive ones will be sent every 5 seconds anyways due to HostData updates
 */
export default (txAdmin: TxAdmin): RoomType => ({
    permission: true, //everyone can see it
    eventName: 'status',
    cumulativeBuffer: false,
    outBuffer: null,
    initialData: () => {
        return getinitialData(txAdmin);
    },
})
