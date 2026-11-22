/* uart_regs.h —offsets reales del driver SPRD UART del kernel A03
 * Fuente: drivers/tty/serial/sprd_serial.c
 *         IverCoder/android_kernel_samsung_a03 @ main
 */
#ifndef IOS_A03_UART_REGS_H
#define IOS_A03_UART_REGS_H

#define SPRD_UART1_BASE   0x200b0000UL   /* alias serial1 del DTB */

#define SPRD_TXD          0x0000U
#define SPRD_RXD          0x0004U
#define SPRD_LSR          0x0008U
#define SPRD_STS1         0x000CU
#define SPRD_IEN          0x0010U
#define SPRD_ICLR         0x0014U
#define SPRD_LCR          0x0018U
#define SPRD_CTL1         0x001CU
#define SPRD_CTL2         0x0020U
#define SPRD_CLKD0        0x0024U
#define SPRD_CLKD1        0x0028U
#define SPRD_IMSR         0x002CU

/* SPRD_STS1 */
#define SPRD_RX_FIFO_CNT_MASK  0x00FFU
#define SPRD_TX_FIFO_CNT_MASK  0xFF00U

/* LCR: 8 datos, 1 stop, sin paridad */
#define SPRD_LCR_DATA_LEN8     0x0CU
#define SPRD_LCR_STOP_1BIT     0x10U
#define SPRD_LCR_8N1           (SPRD_LCR_DATA_LEN8 | SPRD_LCR_STOP_1BIT)

/* Reloj y baud */
#define SPRD_UART_CLK_HZ       26000000UL
#define SPRD_UART_BAUD         115200UL
#define SPRD_UART_DIV          (SPRD_UART_CLK_HZ / SPRD_UART_BAUD)  /* 225 */

#endif /* IOS_A03_UART_REGS_H */
