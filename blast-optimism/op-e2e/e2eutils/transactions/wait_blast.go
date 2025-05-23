package transactions

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

func ForReceiptMaybe(ctx context.Context, client *ethclient.Client, hash common.Hash, status uint64, statusIgnore bool) (*types.Receipt, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		receipt, err := client.TransactionReceipt(ctx, hash)
		if errors.Is(err, ethereum.NotFound) || (err != nil && strings.Contains(err.Error(), "transaction indexing is in progress")) {
			select {
			case <-ctx.Done():
				return nil, fmt.Errorf("timed out waiting for tx %s: %w: %w", hash, err, ctx.Err())
			case <-ticker.C:
				continue
			}
		}
		if errors.Is(err, os.ErrDeadlineExceeded) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("failed to get receipt for tx %s: %w", hash, err)
		}
		if !statusIgnore && receipt.Status != status {
			trace, err := DebugTraceTx(ctx, client, hash)
			if err != nil {
				// still return receipt if trace couldn't be obtained
				return receipt, fmt.Errorf("unexpected receipt status %d, error tracing tx: %w", receipt.Status, err)
			}
			return receipt, &ReceiptStatusError{Status: receipt.Status, TxTrace: trace}
		}
		return receipt, nil
	}
}

type (
	ReceiptStatusError struct {
		Status  uint64
		TxTrace *TxTrace
	}

	CallTrace struct {
		From    common.Address `json:"from"`
		Gas     hexutil.Uint64 `json:"gas"`
		GasUsed hexutil.Uint64 `json:"gasUsed"`
		To      common.Address `json:"to"`
		Input   hexutil.Bytes  `json:"input"`
		Output  hexutil.Bytes  `json:"output"`
		Error   string         `json:"error"`
		Value   hexutil.U256   `json:"value"`
		Type    string         `json:"type"`
	}

	TxTrace struct {
		CallTrace
		Calls []CallTrace `json:"calls"`
	}
)

func (rse *ReceiptStatusError) Error() string {
	return fmt.Sprintf("unexpected receipt status %d (tx trace: %+v)", rse.Status, rse.TxTrace)
}

// DebugTraceTx logs debug_traceTransaction output to aid in debugging unexpected receipt statuses
func DebugTraceTx(ctx context.Context, client *ethclient.Client, txHash common.Hash) (*TxTrace, error) {
	trace := new(TxTrace)
	options := map[string]any{
		"enableReturnData": true,
		"tracer":           "callTracer",
		"tracerConfig":     map[string]any{},
	}
	err := client.Client().CallContext(ctx, trace, "debug_traceTransaction", hexutil.Bytes(txHash.Bytes()), options)
	if err != nil {
		return nil, fmt.Errorf("calling debug_traceTransaction: %w", err)
	}
	return trace, nil
}
